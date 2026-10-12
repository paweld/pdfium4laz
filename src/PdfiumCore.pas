unit PdfiumCore;

{$mode objfpc}{$H+}{$inline on}

interface

uses
  Classes, SysUtils, Graphics, fgl, SyncObjs, PdfiumLib, PdfiumRender;

type
  TPdfPermission = (ppPrint, ppModify, ppCopy, ppAnnotate, ppFillForms, ppExtract, ppAssemble, ppPrintHigh);
  TPdfPermissions = set of TPdfPermission;

  TPdfMetadata = record
    Title: String;
    Author: String;
    Subject: String;
    Keywords: String;
    Creator: String;
    Producer: String;
    CreationDate: String;
    ModDate: String;
  end;

  TPdfPageSize = record
    Width: Double;
    Height: Double;
  end;

  TPdfFormType = (ftNone, ftAcroForm, ftXfaFull, ftXfaForeground);

  { Shared for..in enumerator of the library's index-based lists. }
  generic TPdfEnumerator<T> = class
  public type
    TGetter = function(AIndex: Integer): T of object;
  private
    FGetter: TGetter;
    FCount: Integer;
    FIndex: Integer;
    function GetCurrent: T;
  public
    constructor Create(AGetter: TGetter; ACount: Integer);
    function MoveNext: Boolean;
    property Current: T read GetCurrent;
  end;

  TPdfDocument = class;

  TPdfPage = class
  private
    FOwner: TPdfDocument;
    FIndex: Integer;
    FHandle: FPDF_PAGE;
    constructor Create(AOwner: TPdfDocument; AIndex: Integer);
  public
    destructor Destroy; override;
    function Width: Double;
    function Height: Double;
    function Rotation: Integer;
    { ARotation must be 0, 90, 180 or 270 (degrees clockwise) - any other
      value raises EPdfiumError rather than silently rounding it. }
    procedure SetRotation(ARotation: Integer);
    function HasTransparency: Boolean;
    function RenderToBitmap(AWidth, AHeight: Integer; ABackground: TColor = clWhite): TBitmap;
    { Custom fill/stroke color for paths and text instead of the page's own
      colors (e.g. dark mode). Always blocking - does not expose incremental
      rendering as a public feature. }
    function RenderToBitmapWithColorScheme(AWidth, AHeight: Integer; APathFillColor, APathStrokeColor, ATextFillColor,
      ATextStrokeColor: TColor; ABackground: TColor = clWhite): TBitmap;
    property Handle: FPDF_PAGE read FHandle;
    property PageIndex: Integer read FIndex;
    property Document: TPdfDocument read FOwner;
  end;

  TPdfPageList = specialize TFPGList<TPdfPage>;

  TPdfDocument = class
  private
    FHandle: FPDF_DOCUMENT;
    FFileName: String;
    FStream: TStream;
    FFileAccess: FPDF_FILEACCESS;
    FPages: TPdfPageList;
    FClosing: Boolean;
    FLock: TCriticalSection;
    procedure RemovePage(APage: TPdfPage);
    function GetPageSize(AIndex: Integer): TPdfPageSize;
    function GetPage(AIndex: Integer): TPdfPage;
  public
    constructor Create(const ALibraryPath: String = '');
    destructor Destroy; override;
    procedure LoadFromFile(const AFileName: String; const APassword: String = '');
    procedure LoadFromStream(AStream: TStream; const APassword: String = '');
    procedure Close;
    function IsEncrypted: Boolean;
    function Permissions: TPdfPermissions;
    { Like Permissions, but always reflects the USER password's permissions
      even if the document was opened/unlocked with the owner password -
      Permissions instead reflects whichever password actually opened it. }
    function UserPermissions: TPdfPermissions;
    function Metadata: TPdfMetadata;
    function PageCount: Integer;
    { From the /PageLabels tree (e.g. "i", "A-1"), '' if none. }
    function PageLabel(AIndex: Integer): String;
    { 14 for 1.4, 17 for 1.7, 20 for 2.0, ...; 0 if unknown. }
    function FileVersion: Integer;
    { Raw /ID bytes (not necessarily printable). APermanent selects the first
      (creation-time) vs. the second (most-recent-save) ID value. }
    function FileIdentifier(APermanent: Boolean = True): TBytes;
    function FormType: TPdfFormType;
    function Language: String; // from pdfium/7919
    { Moves the pages at AIndices (0-based, any order, no duplicates) so they
      end up, in the order given, starting at ADestIndex. Every currently
      cached TPdfPage is closed and dropped as part of this call, since each
      one's PageIndex association becomes stale the moment page order
      changes - the next Pages[AIndex] for any index reloads a fresh
      handle for whatever now sits at that index. }
    procedure MovePages(const AIndices: array of Integer; ADestIndex: Integer);
    { Saves the document to ADest. AVersion, when nonzero, forces the PDF
      version of the saved file (same encoding as FileVersion, e.g. 17 for
      1.7) via FPDF_SaveWithVersion; when 0 (the default) FPDF_SaveAsCopy is
      used instead, which keeps the document's own existing version. }
    procedure SaveToStream(ADest: TStream; AVersion: Integer = 0);
    procedure SaveToFile(const AOutputPath: String; AVersion: Integer = 0);
    property Handle: FPDF_DOCUMENT read FHandle;
    property FileName: String read FFileName;
    { 0-based, up to PageCount - 1. Pages are loaded on first access and cached. }
    property Pages[AIndex: Integer]: TPdfPage read GetPage;
    { Cheaper than Pages[AIndex].Width/Height - no FPDF_LoadPage round trip. }
    property PageSizes[AIndex: Integer]: TPdfPageSize read GetPageSize;
    { Per-document PDFium call lock - every raw call touching this document,
      from any thread, must hold it. Internal use by companion units. }
    property Lock: TCriticalSection read FLock;
  end;

implementation

{ TPdfEnumerator }

constructor TPdfEnumerator.Create(AGetter: TGetter; ACount: Integer);
begin
  inherited Create;
  FGetter := AGetter;
  FCount := ACount;
  FIndex := -1;
end;

function TPdfEnumerator.GetCurrent: T;
begin
  Result := FGetter(FIndex);
end;

function TPdfEnumerator.MoveNext: Boolean;
begin
  Inc(FIndex);
  Result := FIndex < FCount;
end;

function StreamGetBlockCallback(AParam: Pointer; APosition: FPDF_ULONG; ABuf: PByte; ASize: FPDF_ULONG): Integer; cdecl;
var
  stream: TStream;
begin
  stream := TStream(AParam);
  stream.Position := APosition;
  if LongWord(stream.Read(ABuf^, ASize)) = ASize then
    Result := 1
  else
    Result := 0;
end;

procedure RaisePdfiumError(const AContext: String);
var
  code: LongWord;
  msg: String;
begin
  code := FPDF_GetLastError();
  case code of
    FPDF_ERR_FILE: msg := 'file not found or could not be opened';
    FPDF_ERR_FORMAT: msg := 'file is not in PDF format or is corrupted';
    FPDF_ERR_PASSWORD: msg := 'a password is required, or the supplied password is incorrect';
    FPDF_ERR_SECURITY: msg := 'unsupported security scheme';
    FPDF_ERR_PAGE: msg := 'page not found or content error';
  else
    msg := 'unknown error';
  end;
  raise EPdfiumError.Create(Format('%s: %s (PDFium error code %d)', [AContext, msg, code]), code);
end;

function GetMetaTag(AHandle: FPDF_DOCUMENT; const ATag: UTF8String): String;
var
  neededBytes: LongWord;
  buffer: array of WideChar;
begin
  Result := '';
  neededBytes := FPDF_GetMetaText(AHandle, PAnsiChar(ATag), nil, 0);
  if neededBytes <= 2 then
    exit;
  SetLength(buffer, neededBytes div 2);
  FPDF_GetMetaText(AHandle, PAnsiChar(ATag), @buffer[0], neededBytes);
  Result := PWideChar(@buffer[0]);
end;

function InterpretPermissions(ARaw: LongWord): TPdfPermissions;
begin
  Result := [];
  if ARaw = $FFFFFFFF then
  begin
    Result := [ppPrint, ppModify, ppCopy, ppAnnotate, ppFillForms, ppExtract, ppAssemble, ppPrintHigh];
    exit;
  end;
  if (ARaw and FPDF_PERM_PRINT) <> 0 then
    Include(Result, ppPrint);
  if (ARaw and FPDF_PERM_MODIFY) <> 0 then
    Include(Result, ppModify);
  if (ARaw and FPDF_PERM_COPY) <> 0 then
    Include(Result, ppCopy);
  if (ARaw and FPDF_PERM_ANNOT_FORMS) <> 0 then
    Include(Result, ppAnnotate);
  if (ARaw and FPDF_PERM_FILL_FORMS) <> 0 then
    Include(Result, ppFillForms);
  if (ARaw and FPDF_PERM_EXTRACT_ACCESS) <> 0 then
    Include(Result, ppExtract);
  if (ARaw and FPDF_PERM_ASSEMBLE) <> 0 then
    Include(Result, ppAssemble);
  if (ARaw and FPDF_PERM_PRINT_HIGH) <> 0 then
    Include(Result, ppPrintHigh);
end;

function ColorToPdfiumArgb(AColor: TColor): FPDF_DWORD;
var
  r, g, b: Byte;
begin
  r := AColor and $FF;
  g := (AColor shr 8) and $FF;
  b := (AColor shr 16) and $FF;
  Result := FPDF_DWORD($FF000000) or (FPDF_DWORD(r) shl 16) or (FPDF_DWORD(g) shl 8) or FPDF_DWORD(b);
end;

{ This PDFium build returns FPDF_RENDER_FAILED if pause is nil - always answer "don't pause" instead. }
function PdfiumNeverPause(pThis: Pointer): FPDF_BOOL; cdecl;
begin
  Result := 0;
end;

type
  TCoreStreamFileWrite = record
    Base: FPDF_FILEWRITE;
    Stream: TStream;
  end;
  PCoreStreamFileWrite = ^TCoreStreamFileWrite;

function CoreStreamWriteBlockCallback(AThis: PFPDF_FILEWRITE; AData: Pointer; ASize: FPDF_ULONG): Integer; cdecl;
begin
  PCoreStreamFileWrite(AThis)^.Stream.WriteBuffer(AData^, ASize);
  Result := 1;
end;

{ TPdfPage }

constructor TPdfPage.Create(AOwner: TPdfDocument; AIndex: Integer);
begin
  inherited Create;
  FOwner := AOwner;
  FIndex := AIndex;
  FOwner.Lock.Enter;
  try
    FHandle := FPDF_LoadPage(AOwner.Handle, AIndex);
  finally
    FOwner.Lock.Leave;
  end;
  if FHandle = nil then
    raise EPdfiumError.Create(Format('Could not load page %d of "%s"', [AIndex, AOwner.FileName]));
end;

destructor TPdfPage.Destroy;
begin
  if FHandle <> nil then
  begin
    FOwner.Lock.Enter;
    try
      FPDF_ClosePage(FHandle);
    finally
      FOwner.Lock.Leave;
    end;
  end;
  if Assigned(FOwner) then
    FOwner.RemovePage(Self);
  inherited Destroy;
end;

function TPdfPage.Width: Double;
begin
  FOwner.Lock.Enter;
  try
    Result := FPDF_GetPageWidthF(FHandle);
  finally
    FOwner.Lock.Leave;
  end;
end;

function TPdfPage.Height: Double;
begin
  FOwner.Lock.Enter;
  try
    Result := FPDF_GetPageHeightF(FHandle);
  finally
    FOwner.Lock.Leave;
  end;
end;

function TPdfPage.Rotation: Integer;
begin
  FOwner.Lock.Enter;
  try
    Result := (FPDFPage_GetRotation(FHandle) mod 4) * 90;
  finally
    FOwner.Lock.Leave;
  end;
end;

procedure TPdfPage.SetRotation(ARotation: Integer);
begin
  if (ARotation <> 0) and (ARotation <> 90) and (ARotation <> 180) and (ARotation <> 270) then
    raise EPdfiumError.Create(Format('SetRotation: %d is not a valid rotation (must be 0, 90, 180 or 270).', [ARotation]));
  FOwner.Lock.Enter;
  try
    FPDFPage_SetRotation(FHandle, (ARotation div 90) mod 4);
  finally
    FOwner.Lock.Leave;
  end;
end;

function TPdfPage.HasTransparency: Boolean;
begin
  FOwner.Lock.Enter;
  try
    Result := FPDFPage_HasTransparency(FHandle) <> 0;
  finally
    FOwner.Lock.Leave;
  end;
end;

function TPdfPage.RenderToBitmap(AWidth, AHeight: Integer; ABackground: TColor): TBitmap;
var
  fpdfBitmap: FPDF_BITMAP;
  r, g, b: Byte;
  bgColor: FPDF_DWORD;
begin
  if (AWidth <= 0) or (AHeight <= 0) then
    raise EPdfiumError.Create('RenderToBitmap: AWidth and AHeight must both be positive.');
  FOwner.Lock.Enter;
  try
    fpdfBitmap := FPDFBitmap_CreateEx(AWidth, AHeight, FPDFBitmap_BGRA, nil, 0);
    if fpdfBitmap = nil then
      raise EPdfiumError.Create('RenderToBitmap: could not allocate an offscreen bitmap.');
    try
      r := ABackground and $FF;
      g := (ABackground shr 8) and $FF;
      b := (ABackground shr 16) and $FF;
      bgColor := FPDF_DWORD($FF000000) or (FPDF_DWORD(r) shl 16) or (FPDF_DWORD(g) shl 8) or FPDF_DWORD(b);
      FPDFBitmap_FillRect(fpdfBitmap, 0, 0, AWidth, AHeight, bgColor);
      FPDF_RenderPageBitmap(fpdfBitmap, FHandle, 0, 0, AWidth, AHeight, 0, FPDF_ANNOT);
      Result := PdfiumBitmapToTBitmap(fpdfBitmap);
    finally
      FPDFBitmap_Destroy(fpdfBitmap);
    end;
  finally
    FOwner.Lock.Leave;
  end;
end;

function TPdfPage.RenderToBitmapWithColorScheme(AWidth, AHeight: Integer; APathFillColor, APathStrokeColor, ATextFillColor,
  ATextStrokeColor: TColor; ABackground: TColor): TBitmap;
var
  fpdfBitmap: FPDF_BITMAP;
  scheme: FPDF_COLORSCHEME;
  pause: IFSDK_PAUSE;
  status: Integer;
begin
  if (AWidth <= 0) or (AHeight <= 0) then
    raise EPdfiumError.Create('RenderToBitmapWithColorScheme: AWidth and AHeight must both be positive.');
  scheme.path_fill_color := ColorToPdfiumArgb(APathFillColor);
  scheme.path_stroke_color := ColorToPdfiumArgb(APathStrokeColor);
  scheme.text_fill_color := ColorToPdfiumArgb(ATextFillColor);
  scheme.text_stroke_color := ColorToPdfiumArgb(ATextStrokeColor);
  pause.version := 1;
  pause.NeedToPauseNow := @PdfiumNeverPause;
  pause.user := nil;
  FOwner.Lock.Enter;
  try
    fpdfBitmap := FPDFBitmap_CreateEx(AWidth, AHeight, FPDFBitmap_BGRA, nil, 0);
    if fpdfBitmap = nil then
      raise EPdfiumError.Create('RenderToBitmapWithColorScheme: could not allocate an offscreen bitmap.');
    try
      FPDFBitmap_FillRect(fpdfBitmap, 0, 0, AWidth, AHeight, ColorToPdfiumArgb(ABackground));
      status := FPDF_RenderPageBitmapWithColorScheme_Start(fpdfBitmap, FHandle, 0, 0, AWidth, AHeight, 0, FPDF_ANNOT, @scheme, @pause);
      try
        while status = FPDF_RENDER_TOBECONTINUED do
          status := FPDF_RenderPage_Continue(FHandle, @pause);
      finally
        FPDF_RenderPage_Close(FHandle);
      end;
      if status <> FPDF_RENDER_DONE then
        raise EPdfiumError.Create(Format('RenderToBitmapWithColorScheme: rendering failed (status %d).', [status]));
      Result := PdfiumBitmapToTBitmap(fpdfBitmap);
    finally
      FPDFBitmap_Destroy(fpdfBitmap);
    end;
  finally
    FOwner.Lock.Leave;
  end;
end;

{ TPdfDocument }

constructor TPdfDocument.Create(const ALibraryPath: String = '');
begin
  inherited Create;
  FLock := TPdfiumLock.Create;
  PdfiumInitialize(ALibraryPath);
  FPages := TPdfPageList.Create;
end;

destructor TPdfDocument.Destroy;
begin
  Close;
  FPages.Free;
  FLock.Free;
  PdfiumFinalize;
  inherited Destroy;
end;

procedure TPdfDocument.LoadFromFile(const AFileName: String; const APassword: String = '');
begin
  Close;
  FLock.Enter;
  try
    FHandle := FPDF_LoadDocument(PAnsiChar(UTF8String(AFileName)), PAnsiChar(UTF8String(APassword)));
  finally
    FLock.Leave;
  end;
  if FHandle = nil then
    RaisePdfiumError(Format('Could not open document "%s"', [AFileName]));
  FFileName := AFileName;
end;

procedure TPdfDocument.LoadFromStream(AStream: TStream; const APassword: String = '');
begin
  if AStream = nil then
    raise EPdfiumError.Create('LoadFromStream: AStream must not be nil.');
  Close;
  FStream := AStream;
  FFileAccess.m_FileLen := AStream.Size;
  FFileAccess.m_GetBlock := @StreamGetBlockCallback;
  FFileAccess.m_Param := AStream;
  FLock.Enter;
  try
    FHandle := FPDF_LoadCustomDocument(@FFileAccess, PAnsiChar(UTF8String(APassword)));
  finally
    FLock.Leave;
  end;
  if FHandle = nil then
  begin
    FStream := nil;
    RaisePdfiumError('Could not open document from stream');
  end;
end;

procedure TPdfDocument.Close;
var
  i: Integer;
begin
  if FHandle = nil then
    exit;
  FClosing := True;
  FLock.Enter;
  try
    for i := FPages.Count - 1 downto 0 do
      FPages[i].Free;
    FPages.Clear;
    FPDF_CloseDocument(FHandle);
    FHandle := nil;
  finally
    FLock.Leave;
  end;
  FFileName := '';
  FStream := nil;
  FClosing := False;
end;

procedure TPdfDocument.RemovePage(APage: TPdfPage);
begin
  if FClosing then
    exit;
  FPages.Remove(APage);
end;

function TPdfDocument.IsEncrypted: Boolean;
begin
  FLock.Enter;
  try
    Result := FPDF_GetSecurityHandlerRevision(FHandle) >= 0;
  finally
    FLock.Leave;
  end;
end;

function TPdfDocument.Permissions: TPdfPermissions;
var
  raw: LongWord;
begin
  FLock.Enter;
  try
    raw := FPDF_GetDocPermissions(FHandle);
  finally
    FLock.Leave;
  end;
  Result := InterpretPermissions(raw);
end;

function TPdfDocument.UserPermissions: TPdfPermissions;
var
  raw: LongWord;
begin
  FLock.Enter;
  try
    raw := FPDF_GetDocUserPermissions(FHandle);
  finally
    FLock.Leave;
  end;
  Result := InterpretPermissions(raw);
end;

function TPdfDocument.Metadata: TPdfMetadata;
begin
  FLock.Enter;
  try
    Result.Title := GetMetaTag(FHandle, 'Title');
    Result.Author := GetMetaTag(FHandle, 'Author');
    Result.Subject := GetMetaTag(FHandle, 'Subject');
    Result.Keywords := GetMetaTag(FHandle, 'Keywords');
    Result.Creator := GetMetaTag(FHandle, 'Creator');
    Result.Producer := GetMetaTag(FHandle, 'Producer');
    Result.CreationDate := GetMetaTag(FHandle, 'CreationDate');
    Result.ModDate := GetMetaTag(FHandle, 'ModDate');
  finally
    FLock.Leave;
  end;
end;

function TPdfDocument.PageCount: Integer;
begin
  FLock.Enter;
  try
    Result := FPDF_GetPageCount(FHandle);
  finally
    FLock.Leave;
  end;
end;

function TPdfDocument.GetPageSize(AIndex: Integer): TPdfPageSize;
var
  size: FS_SIZEF;
begin
  Result.Width := 0;
  Result.Height := 0;
  FLock.Enter;
  try
    if FPDF_GetPageSizeByIndexF(FHandle, AIndex, size) = 0 then
      raise EPdfiumError.Create(Format('PageSizes[]: could not determine the size of page %d.', [AIndex]));
    Result.Width := size.width;
    Result.Height := size.height;
  finally
    FLock.Leave;
  end;
end;

function TPdfDocument.PageLabel(AIndex: Integer): String;
var
  neededBytes: LongWord;
  buffer: array of WideChar;
begin
  Result := '';
  FLock.Enter;
  try
    neededBytes := FPDF_GetPageLabel(FHandle, AIndex, nil, 0);
    if neededBytes <= 2 then
      exit;
    SetLength(buffer, neededBytes div 2);
    FPDF_GetPageLabel(FHandle, AIndex, @buffer[0], neededBytes);
    Result := PWideChar(@buffer[0]);
  finally
    FLock.Leave;
  end;
end;

function TPdfDocument.FileVersion: Integer;
begin
  Result := 0;
  FLock.Enter;
  try
    FPDF_GetFileVersion(FHandle, Result);
  finally
    FLock.Leave;
  end;
end;

function TPdfDocument.FileIdentifier(APermanent: Boolean): TBytes;
var
  idType: Integer;
  neededBytes: LongWord;
begin
  SetLength(Result, 0);
  if APermanent then
    idType := FILEIDTYPE_PERMANENT
  else
    idType := FILEIDTYPE_CHANGING;
  FLock.Enter;
  try
    neededBytes := FPDF_GetFileIdentifier(FHandle, idType, nil, 0);
    if neededBytes = 0 then
      exit;
    SetLength(Result, neededBytes);
    FPDF_GetFileIdentifier(FHandle, idType, @Result[0], neededBytes);
  finally
    FLock.Leave;
  end;
end;

function TPdfDocument.FormType: TPdfFormType;
var
  raw: Integer;
begin
  FLock.Enter;
  try
    raw := FPDF_GetFormType(FHandle);
  finally
    FLock.Leave;
  end;
  case raw of
    FORMTYPE_ACRO_FORM: Result := ftAcroForm;
    FORMTYPE_XFA_FULL: Result := ftXfaFull;
    FORMTYPE_XFA_FOREGROUND: Result := ftXfaForeground;
  else
    Result := ftNone;
  end;
end;

function TPdfDocument.Language: String;
var
  neededBytes: LongWord;
  buffer: array of WideChar;
begin
  Result := '';
  if not Assigned(FPDFCatalog_GetLanguage) then
    exit;
  FLock.Enter;
  try
    neededBytes := FPDFCatalog_GetLanguage(FHandle, nil, 0);
    if neededBytes <= 2 then
      exit;
    SetLength(buffer, neededBytes div 2);
    FPDFCatalog_GetLanguage(FHandle, @buffer[0], neededBytes);
    Result := PWideChar(@buffer[0]);
  finally
    FLock.Leave;
  end;
end;

function TPdfDocument.GetPage(AIndex: Integer): TPdfPage;
var
  i: Integer;
begin
  if (AIndex < 0) or (AIndex >= PageCount) then
    raise EPdfiumError.Create(Format('Pages[]: page index %d is out of range (0..%d).', [AIndex, PageCount - 1]));
  for i := 0 to FPages.Count - 1 do
    if FPages[i].PageIndex = AIndex then
    begin
      Result := FPages[i];
      exit;
    end;
  Result := TPdfPage.Create(Self, AIndex);
  FPages.Add(Result);
end;

procedure TPdfDocument.MovePages(const AIndices: array of Integer; ADestIndex: Integer);
var
  indices: array of Integer;
  i: Integer;
  ok: FPDF_BOOL;
begin
  if Length(AIndices) = 0 then
    raise EPdfiumError.Create('MovePages: AIndices must not be empty.');
  SetLength(indices, Length(AIndices));
  for i := 0 to High(AIndices) do
    indices[i] := AIndices[i];
  FLock.Enter;
  try
    ok := FPDF_MovePages(FHandle, @indices[0], Length(indices), ADestIndex);
  finally
    FLock.Leave;
  end;
  if ok = 0 then
    raise EPdfiumError.Create('MovePages: failed to move the requested pages (out-of-range or duplicate index?).');
  for i := FPages.Count - 1 downto 0 do
    FPages[i].Free;
end;

procedure TPdfDocument.SaveToStream(ADest: TStream; AVersion: Integer);
var
  sfw: TCoreStreamFileWrite;
  ok: FPDF_BOOL;
begin
  sfw.Base.version := 1;
  sfw.Base.WriteBlock := @CoreStreamWriteBlockCallback;
  sfw.Stream := ADest;
  FLock.Enter;
  try
    if AVersion <> 0 then
      ok := FPDF_SaveWithVersion(FHandle, @sfw.Base, 0, AVersion)
    else
      ok := FPDF_SaveAsCopy(FHandle, @sfw.Base, 0);
  finally
    FLock.Leave;
  end;
  if ok = 0 then
    raise EPdfiumError.Create('SaveToStream: could not save the document.');
end;

procedure TPdfDocument.SaveToFile(const AOutputPath: String; AVersion: Integer);
var
  stream: TFileStream;
begin
  stream := TFileStream.Create(AOutputPath, fmCreate);
  try
    SaveToStream(stream, AVersion);
  finally
    stream.Free;
  end;
end;

end.
