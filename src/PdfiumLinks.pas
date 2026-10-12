unit PdfiumLinks;

{$mode objfpc}{$H+}{$inline on}

interface

uses
  Classes, SysUtils, Types, PdfiumLib, PdfiumCore;

type
  TPdfLinkKind = (lkURI, lkGoto, lkRemoteGoto, lkLaunch, lkUnknown);

  TPdfLink = record
    Kind: TPdfLinkKind;
    Bounds: TRectF;
    URI: String;
    PageIndex: Integer;
    FilePath: String;
  end;

  TPdfLinkList = class
  private
    FPage: TPdfPage;
    FLinks: array of TPdfLink;
    function GetLink(AIndex: Integer): TPdfLink;
  public type
    TEnumerator = specialize TPdfEnumerator<TPdfLink>;
  public
    function GetEnumerator: TEnumerator;
    constructor Create(APage: TPdfPage);
    function Count: Integer;
    property Page: TPdfPage read FPage;
    property Items[AIndex: Integer]: TPdfLink read GetLink; default;
  end;

  TPdfPageLinksHelper = class helper for TPdfPage
    function Links: TPdfLinkList;
  end;

implementation

procedure FillLinkInfo(ADocHandle: FPDF_DOCUMENT; ALinkAnnot: FPDF_LINK; out ALink: TPdfLink);
var
  rect: FS_RECTF;
  action: FPDF_ACTION;
  dest: FPDF_DEST;
  neededBytes: LongWord;
  abuffer: array of AnsiChar;
  utf8Buf: UTF8String;
begin
  FillChar(ALink, SizeOf(ALink), 0);
  ALink.Kind := lkUnknown;
  ALink.PageIndex := -1;
  if FPDFLink_GetAnnotRect(ALinkAnnot, rect) <> 0 then
  begin
    ALink.Bounds.Left := rect.Left;
    ALink.Bounds.Top := rect.Top;
    ALink.Bounds.Right := rect.Right;
    ALink.Bounds.Bottom := rect.Bottom;
  end;
  action := FPDFLink_GetAction(ALinkAnnot);
  if action <> nil then
  begin
    case FPDFAction_GetType(action) of
      PDFACTION_GOTO:
      begin
        ALink.Kind := lkGoto;
        dest := FPDFAction_GetDest(ADocHandle, action);
        if dest <> nil then
          ALink.PageIndex := FPDFDest_GetDestPageIndex(ADocHandle, dest);
      end;
      PDFACTION_REMOTEGOTO:
      begin
        ALink.Kind := lkRemoteGoto;
        neededBytes := FPDFAction_GetFilePath(action, nil, 0);
        if neededBytes > 1 then
        begin
          SetLength(abuffer, neededBytes);
          FPDFAction_GetFilePath(action, @abuffer[0], neededBytes);
          utf8Buf := PAnsiChar(@abuffer[0]);
          ALink.FilePath := utf8Buf;
        end;
      end;
      PDFACTION_URI:
      begin
        ALink.Kind := lkURI;
        neededBytes := FPDFAction_GetURIPath(ADocHandle, action, nil, 0);
        if neededBytes > 1 then
        begin
          SetLength(abuffer, neededBytes);
          FPDFAction_GetURIPath(ADocHandle, action, @abuffer[0], neededBytes);
          utf8Buf := PAnsiChar(@abuffer[0]);
          ALink.URI := utf8Buf;
        end;
      end;
      PDFACTION_LAUNCH:
      begin
        ALink.Kind := lkLaunch;
        neededBytes := FPDFAction_GetFilePath(action, nil, 0);
        if neededBytes > 1 then
        begin
          SetLength(abuffer, neededBytes);
          FPDFAction_GetFilePath(action, @abuffer[0], neededBytes);
          utf8Buf := PAnsiChar(@abuffer[0]);
          ALink.FilePath := utf8Buf;
        end;
      end;
    end;
  end
  else
  begin
    dest := FPDFLink_GetDest(ADocHandle, ALinkAnnot);
    if dest <> nil then
    begin
      ALink.Kind := lkGoto;
      ALink.PageIndex := FPDFDest_GetDestPageIndex(ADocHandle, dest);
    end;
  end;
end;

{ TPdfLinkList }

constructor TPdfLinkList.Create(APage: TPdfPage);
var
  startPos: Integer;
  linkAnnot: FPDF_LINK;
  docHandle: FPDF_DOCUMENT;
  n: Integer;
begin
  inherited Create;
  FPage := APage;
  APage.Document.Lock.Enter;
  try
    docHandle := APage.Document.Handle;
    startPos := 0;
    n := 0;
    while FPDFLink_Enumerate(APage.Handle, startPos, linkAnnot) <> 0 do
    begin
      SetLength(FLinks, n + 1);
      FillLinkInfo(docHandle, linkAnnot, FLinks[n]);
      Inc(n);
    end;
  finally
    APage.Document.Lock.Leave;
  end;
end;

function TPdfLinkList.Count: Integer;
begin
  Result := Length(FLinks);
end;

function TPdfLinkList.GetEnumerator: TEnumerator;
begin
  Result := TEnumerator.Create(@GetLink, Count);
end;

function TPdfLinkList.GetLink(AIndex: Integer): TPdfLink;
begin
  if (AIndex < 0) or (AIndex >= Length(FLinks)) then
    raise EPdfiumError.Create(Format('TPdfLinkList[]: link index %d is out of range (0..%d).', [AIndex, Length(FLinks) - 1]));
  Result := FLinks[AIndex];
end;

{ TPdfPageLinksHelper }

function TPdfPageLinksHelper.Links: TPdfLinkList;
begin
  Result := TPdfLinkList.Create(Self);
end;

end.
