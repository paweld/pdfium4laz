unit PdfiumBookmarks;

{$mode objfpc}{$H+}{$inline on}

interface

uses
  Classes, SysUtils, Graphics, PdfiumLib, PdfiumCore;

type
  TPdfBookmark = class
  private
    FDocHandle: FPDF_DOCUMENT;
    FHandle: FPDF_BOOKMARK;
    FParent: TPdfBookmark;
    FChildren: array of TPdfBookmark;
    FTitle: String;
    FPageIndex: Integer;
    FPageY: Double;
    FHasColor: Boolean;
    FColor: TColor;
    constructor Create(ADocHandle: FPDF_DOCUMENT; AHandle: FPDF_BOOKMARK; AParent: TPdfBookmark);
    function GetChild(AIndex: Integer): TPdfBookmark;
  public type
    TEnumerator = specialize TPdfEnumerator<TPdfBookmark>;
  public
    function GetEnumerator: TEnumerator;
    destructor Destroy; override;
    function Title: String;
    function HasColor(out AColor: TColor): Boolean; // from pdfium/7919
    function PageIndex: Integer;
    function PageY: Double;
    function ChildCount: Integer;
    function Parent: TPdfBookmark;
    property Children[AIndex: Integer]: TPdfBookmark read GetChild; default;
  end;

  TPdfBookmarkTree = class
  private
    FDocument: TPdfDocument;
    FRoots: array of TPdfBookmark;
    function GetRoot(AIndex: Integer): TPdfBookmark;
  public type
    TEnumerator = specialize TPdfEnumerator<TPdfBookmark>;
  public
    function GetEnumerator: TEnumerator;
    constructor Create(ADocument: TPdfDocument);
    destructor Destroy; override;
    procedure RefreshBookmarks;
    function RootCount: Integer;
    property Document: TPdfDocument read FDocument;
    property Roots[AIndex: Integer]: TPdfBookmark read GetRoot; default;
  end;

implementation

function HandleAlreadyVisited(AVisited: TFPList; AHandle: Pointer): Boolean;
begin
  Result := AVisited.IndexOf(AHandle) >= 0;
end;

{ Caller must hold the owning document's Lock for the whole recursive call. }
function BuildNode(ADocHandle: FPDF_DOCUMENT; AHandle: FPDF_BOOKMARK; AParent: TPdfBookmark; AVisited: TFPList): TPdfBookmark;
var
  childHandle: FPDF_BOOKMARK;
  n: Integer;
begin
  Result := TPdfBookmark.Create(ADocHandle, AHandle, AParent);
  AVisited.Add(AHandle);
  n := 0;
  childHandle := FPDFBookmark_GetFirstChild(ADocHandle, AHandle);
  while (childHandle <> nil) and not HandleAlreadyVisited(AVisited, childHandle) do
  begin
    SetLength(Result.FChildren, n + 1);
    Result.FChildren[n] := BuildNode(ADocHandle, childHandle, Result, AVisited);
    Inc(n);
    childHandle := FPDFBookmark_GetNextSibling(ADocHandle, childHandle);
  end;
end;

{ TPdfBookmark }

constructor TPdfBookmark.Create(ADocHandle: FPDF_DOCUMENT; AHandle: FPDF_BOOKMARK; AParent: TPdfBookmark);
var
  neededBytes: LongWord;
  buffer: array of WideChar;
  dest: FPDF_DEST;
  action: FPDF_ACTION;
  r, g, b: Single;
  hasX, hasY, hasZoom: FPDF_BOOL;
  x, y, zoom: Single;
begin
  inherited Create;
  FDocHandle := ADocHandle;
  FHandle := AHandle;
  FParent := AParent;
  FTitle := '';
  neededBytes := FPDFBookmark_GetTitle(FHandle, nil, 0);
  if neededBytes > 2 then
  begin
    SetLength(buffer, neededBytes div 2);
    FPDFBookmark_GetTitle(FHandle, @buffer[0], neededBytes);
    FTitle := PWideChar(@buffer[0]);
  end;
  FColor := clDefault;
  FHasColor := Assigned(FPDFBookmark_GetColor) and (FPDFBookmark_GetColor(FHandle, r, g, b) <> 0);
  if FHasColor then
    FColor := RGBToColor(Round(r * 255), Round(g * 255), Round(b * 255));
  FPageIndex := -1;
  FPageY := 0;
  dest := FPDFBookmark_GetDest(FDocHandle, FHandle);
  if dest = nil then
  begin
    action := FPDFBookmark_GetAction(FHandle);
    if (action <> nil) and (FPDFAction_GetType(action) = PDFACTION_GOTO) then
      dest := FPDFAction_GetDest(FDocHandle, action);
  end;
  if dest <> nil then
  begin
    FPageIndex := FPDFDest_GetDestPageIndex(FDocHandle, dest);
    if (FPDFDest_GetLocationInPage(dest, hasX, hasY, hasZoom, x, y, zoom) <> 0) and (hasY <> 0) then
      FPageY := y;
  end;
end;

destructor TPdfBookmark.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FChildren) do
    FChildren[i].Free;
  inherited Destroy;
end;

function TPdfBookmark.Title: String;
begin
  Result := FTitle;
end;

function TPdfBookmark.HasColor(out AColor: TColor): Boolean;
begin
  AColor := FColor;
  Result := FHasColor;
end;

function TPdfBookmark.PageIndex: Integer;
begin
  Result := FPageIndex;
end;

function TPdfBookmark.PageY: Double;
begin
  Result := FPageY;
end;

function TPdfBookmark.ChildCount: Integer;
begin
  Result := Length(FChildren);
end;

function TPdfBookmark.GetEnumerator: TEnumerator;
begin
  Result := TEnumerator.Create(@GetChild, ChildCount);
end;

function TPdfBookmark.GetChild(AIndex: Integer): TPdfBookmark;
begin
  if (AIndex < 0) or (AIndex >= Length(FChildren)) then
    raise EPdfiumError.Create(Format('Children[]: child index %d is out of range (0..%d).', [AIndex, Length(FChildren) - 1]));
  Result := FChildren[AIndex];
end;

function TPdfBookmark.Parent: TPdfBookmark;
begin
  Result := FParent;
end;

{ TPdfBookmarkTree }

constructor TPdfBookmarkTree.Create(ADocument: TPdfDocument);
begin
  inherited Create;
  FDocument := ADocument;
  RefreshBookmarks;
end;

destructor TPdfBookmarkTree.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FRoots) do
    FRoots[i].Free;
  inherited Destroy;
end;

procedure TPdfBookmarkTree.RefreshBookmarks;
var
  handle: FPDF_BOOKMARK;
  visited: TFPList;
  n, i: Integer;
begin
  for i := 0 to High(FRoots) do
    FRoots[i].Free;
  SetLength(FRoots, 0);
  n := 0;
  visited := TFPList.Create;
  try
    FDocument.Lock.Enter;
    try
      handle := FPDFBookmark_GetFirstChild(FDocument.Handle, nil);
      while (handle <> nil) and not HandleAlreadyVisited(visited, handle) do
      begin
        SetLength(FRoots, n + 1);
        FRoots[n] := BuildNode(FDocument.Handle, handle, nil, visited);
        Inc(n);
        handle := FPDFBookmark_GetNextSibling(FDocument.Handle, handle);
      end;
    finally
      FDocument.Lock.Leave;
    end;
  finally
    visited.Free;
  end;
end;

function TPdfBookmarkTree.RootCount: Integer;
begin
  Result := Length(FRoots);
end;

function TPdfBookmarkTree.GetEnumerator: TEnumerator;
begin
  Result := TEnumerator.Create(@GetRoot, RootCount);
end;

function TPdfBookmarkTree.GetRoot(AIndex: Integer): TPdfBookmark;
begin
  if (AIndex < 0) or (AIndex >= Length(FRoots)) then
    raise EPdfiumError.Create(Format('TPdfBookmarkTree[]: root index %d is out of range (0..%d).', [AIndex, Length(FRoots) - 1]));
  Result := FRoots[AIndex];
end;

end.
