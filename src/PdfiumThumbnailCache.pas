unit PdfiumThumbnailCache;

{$mode objfpc}{$H+}{$inline on}

interface

uses
  Classes, SysUtils, Types, SyncObjs, Graphics, PdfiumLib, PdfiumCore, PdfiumRender;

type
  TPdfThumbnailReadyEvent = procedure(Sender: TObject; APageIndex: Integer) of object;

  { SrcBitmap must be destroyed under the document's Lock once done with. }
  TPdfThumbCompositeJob = record
    DestRect: TRect;
    Matrix: FS_MATRIX;
    SrcBitmap: FPDF_BITMAP;
  end;
  TPdfThumbCompositeJobArray = array of TPdfThumbCompositeJob;

  { Works directly against raw FPDF_DOCUMENT/FPDF_PAGE handles, not
    TPdfDocument.Pages[], so it never touches TPdfDocument's own
    page-ownership bookkeeping from a non-owning thread. }
  TPdfThumbnailCache = class(TThread)
  private
    FDocHandle: FPDF_DOCUMENT;
    { Borrowed from the owning TPdfDocument.Lock - not owned/freed here. }
    FPdfLock: TCriticalSection;
    FThumbnailWidth: Integer;
    FPageCount: Integer;
    FBitmaps: TThreadList;
    FPendingLock: TCriticalSection;
    FPending: array of Integer;
    FOnThumbnailReady: TPdfThumbnailReadyEvent;
    { Fixed for this cache's lifetime - changing it means recreating the
      cache (see TPdfThumbnailPanel.InvalidateCache), not a live update. }
    FColorScheme: TPdfColorScheme;
    FConvertSource: FPDF_BITMAP;
    FConvertResult: TBitmap;
    FResizeTargetW, FResizeTargetH: Integer;
    { KNOWN GOTCHA: these must only be applied via Synchronize AFTER FPdfLock
      is released and the page closed - doing it earlier, still holding the
      lock, reproducibly hung the render thread. }
    FCompositeBmp: TBitmap;
    FCompositeDestRect: TRect;
    FCompositeSrcBitmap: FPDF_BITMAP;
    FCompositeMatrix: FS_MATRIX;
    FCompositePageWidth, FCompositePageHeight: Double;
    FCompositeJobW, FCompositeJobH: Integer;
    function PopNextIndex: Integer;
    function PrepareColorSchemeBitmap(APage: FPDF_PAGE; AWidth, AHeight: Integer; APageWidth, APageHeight: Single;
      out AJobs: TPdfThumbCompositeJobArray): FPDF_BITMAP;
    procedure RenderOne(AIndex: Integer);
    procedure QueueReady(AIndex: Integer);
    procedure DoConvertBitmap;
    procedure DoResizeConvertedBitmap;
    procedure DoCompositeCurrentImage;
    { FPC does not support a default value for a record-typed parameter,
      hence a second constructor instead of a defaulted AScheme parameter. }
    procedure InitCache(ADocument: TPdfDocument; AThumbnailWidth: Integer; AOnThumbnailReady: TPdfThumbnailReadyEvent;
      const AScheme: TPdfColorScheme);
  protected
    procedure Execute; override;
  public
    constructor Create(ADocument: TPdfDocument; AThumbnailWidth: Integer; AOnThumbnailReady: TPdfThumbnailReadyEvent = nil);
    constructor CreateWithScheme(ADocument: TPdfDocument; AThumbnailWidth: Integer; const AScheme: TPdfColorScheme;
      AOnThumbnailReady: TPdfThumbnailReadyEvent = nil);
    destructor Destroy; override;
    procedure Prioritize(APageIndex: Integer);
    function GetBitmap(APageIndex: Integer): TBitmap;
    property PageCount: Integer read FPageCount;
    property ThumbnailWidth: Integer read FThumbnailWidth;
    property OnThumbnailReady: TPdfThumbnailReadyEvent read FOnThumbnailReady write FOnThumbnailReady;
  end;

implementation

type
  TThumbnailReadyNotifier = class
  private
    FCallback: TPdfThumbnailReadyEvent;
    FSender: TObject;
    FPageIndex: Integer;
  public
    constructor Create(ASender: TObject; ACallback: TPdfThumbnailReadyEvent; APageIndex: Integer);
    procedure Notify;
  end;

constructor TThumbnailReadyNotifier.Create(ASender: TObject; ACallback: TPdfThumbnailReadyEvent; APageIndex: Integer);
begin
  inherited Create;
  FSender := ASender;
  FCallback := ACallback;
  FPageIndex := APageIndex;
end;

procedure TThumbnailReadyNotifier.Notify;
begin
  if Assigned(FCallback) then
    FCallback(FSender, FPageIndex);
  Free;
end;

{ TPdfThumbnailCache }

constructor TPdfThumbnailCache.Create(ADocument: TPdfDocument; AThumbnailWidth: Integer; AOnThumbnailReady: TPdfThumbnailReadyEvent = nil);
var
  disabledScheme: TPdfColorScheme;
begin
  inherited Create(True);
  FillChar(disabledScheme, SizeOf(disabledScheme), 0);
  InitCache(ADocument, AThumbnailWidth, AOnThumbnailReady, disabledScheme);
end;

constructor TPdfThumbnailCache.CreateWithScheme(ADocument: TPdfDocument; AThumbnailWidth: Integer; const AScheme: TPdfColorScheme;
  AOnThumbnailReady: TPdfThumbnailReadyEvent = nil);
begin
  inherited Create(True);
  InitCache(ADocument, AThumbnailWidth, AOnThumbnailReady, AScheme);
end;

procedure TPdfThumbnailCache.InitCache(ADocument: TPdfDocument; AThumbnailWidth: Integer; AOnThumbnailReady: TPdfThumbnailReadyEvent;
  const AScheme: TPdfColorScheme);
var
  i: Integer;
  list: TList;
begin
  FreeOnTerminate := False;
  Priority := tpLower; // must not starve TPdfRenderWorker (PdfiumViewer.pas) for the document's Lock
  FDocHandle := ADocument.Handle;
  FPdfLock := ADocument.Lock;
  FThumbnailWidth := AThumbnailWidth;
  FPageCount := ADocument.PageCount;
  FOnThumbnailReady := AOnThumbnailReady;
  FColorScheme := AScheme;
  FPendingLock := TCriticalSection.Create;
  FBitmaps := TThreadList.Create;
  list := FBitmaps.LockList;
  try
    list.Count := FPageCount;
  finally
    FBitmaps.UnlockList;
  end;
  SetLength(FPending, FPageCount);
  for i := 0 to FPageCount - 1 do
    FPending[i] := i;
  Start;
end;

destructor TPdfThumbnailCache.Destroy;
var
  i: Integer;
  list: TList;
begin
  Terminate;
  WaitFor;
  list := FBitmaps.LockList;
  try
    for i := 0 to list.Count - 1 do
    begin
      if list[i] <> nil then
        TBitmap(list[i]).Free;
    end;
  finally
    FBitmaps.UnlockList;
  end;
  FBitmaps.Free;
  FPendingLock.Free;
  inherited Destroy;
end;

function TPdfThumbnailCache.PopNextIndex: Integer;
begin
  FPendingLock.Enter;
  try
    if Length(FPending) = 0 then
      Result := -1
    else
    begin
      Result := FPending[0];
      if Length(FPending) > 1 then
        Move(FPending[1], FPending[0], (Length(FPending) - 1) * SizeOf(Integer));
      SetLength(FPending, Length(FPending) - 1);
    end;
  finally
    FPendingLock.Leave;
  end;
end;

procedure TPdfThumbnailCache.Prioritize(APageIndex: Integer);
var
  i: Integer;
begin
  FPendingLock.Enter;
  try
    for i := 0 to High(FPending) do
    begin
      if FPending[i] = APageIndex then
      begin
        if i > 0 then
        begin
          Move(FPending[0], FPending[1], i * SizeOf(Integer));
          FPending[0] := APageIndex;
        end;
        break;
      end;
    end;
  finally
    FPendingLock.Leave;
  end;
end;

procedure TPdfThumbnailCache.QueueReady(AIndex: Integer);
var
  notifier: TThumbnailReadyNotifier;
begin
  if Assigned(FOnThumbnailReady) then
  begin
    notifier := TThumbnailReadyNotifier.Create(Self, FOnThumbnailReady, AIndex);
    Queue(@notifier.Notify);
  end;
end;

procedure TPdfThumbnailCache.DoConvertBitmap;
begin
  { Safe: RenderOne always releases FPdfLock before Synchronize'ing here. }
  FPdfLock.Enter;
  try
    FConvertResult := PdfiumBitmapToTBitmap(FConvertSource);
  finally
    FPdfLock.Leave;
  end;
end;

procedure TPdfThumbnailCache.DoResizeConvertedBitmap;
var
  resized: TBitmap;
begin
  resized := TBitmap.Create;
  resized.PixelFormat := pf32bit;
  resized.SetSize(FResizeTargetW, FResizeTargetH);
  resized.Canvas.StretchDraw(Rect(0, 0, FResizeTargetW, FResizeTargetH), FConvertResult);
  FConvertResult.Free;
  FConvertResult := resized;
end;

procedure TPdfThumbnailCache.DoCompositeCurrentImage;
begin
  FPdfLock.Enter;
  try
    CompositeImagePixels(FCompositeBmp, FCompositeDestRect, FCompositeSrcBitmap, FCompositeMatrix,
      FCompositePageWidth, FCompositePageHeight, FCompositeJobW, FCompositeJobH, FColorScheme.InvertImages);
  finally
    FPdfLock.Leave;
  end;
end;

function ColorToArgb(AColor: TColor): FPDF_DWORD;
var
  r, g, b: Byte;
begin
  AColor := ColorToRGB(AColor);
  r := AColor and $FF;
  g := (AColor shr 8) and $FF;
  b := (AColor shr 16) and $FF;
  Result := FPDF_DWORD($FF000000) or (FPDF_DWORD(r) shl 16) or (FPDF_DWORD(g) shl 8) or FPDF_DWORD(b);
end;

{ This PDFium build returns FPDF_RENDER_FAILED if pause is nil - always answer "don't pause" instead. }
function ThumbNeverPause(pThis: Pointer): FPDF_BOOL; cdecl;
begin
  Result := 0;
end;

{ Only raw PDFium calls here, no Synchronize - compositing itself happens
  later in RenderOne, after the lock/page scope ends. No embedded-thumbnail
  fast path: that bitmap is already flattened/colored and can't be recolored. }
function TPdfThumbnailCache.PrepareColorSchemeBitmap(APage: FPDF_PAGE; AWidth, AHeight: Integer;
  APageWidth, APageHeight: Single; out AJobs: TPdfThumbCompositeJobArray): FPDF_BITMAP;
var
  scheme: FPDF_COLORSCHEME;
  pause: IFSDK_PAUSE;
  status: Integer;
  objCount, i, jobCount: Integer;
  pageObj: FPDF_PAGEOBJECT;
  l, b, r, t: Single;
  mtx: FS_MATRIX;
  destRect: TRect;
  srcImageBitmap: FPDF_BITMAP;
begin
  SetLength(AJobs, 0);
  Result := FPDFBitmap_CreateEx(AWidth, AHeight, FPDFBitmap_BGRA, nil, 0);
  if Result = nil then
    exit;
  scheme.path_fill_color := ColorToArgb(FColorScheme.PathFillColor);
  scheme.path_stroke_color := ColorToArgb(FColorScheme.PathStrokeColor);
  scheme.text_fill_color := ColorToArgb(FColorScheme.TextFillColor);
  scheme.text_stroke_color := ColorToArgb(FColorScheme.TextStrokeColor);
  pause.version := 1;
  pause.NeedToPauseNow := @ThumbNeverPause;
  pause.user := nil;
  FPDFBitmap_FillRect(Result, 0, 0, AWidth, AHeight, ColorToArgb(FColorScheme.BackgroundColor));
  status := FPDF_RenderPageBitmapWithColorScheme_Start(Result, APage, 0, 0, AWidth, AHeight, 0, FPDF_ANNOT, @scheme, @pause);
  while status = FPDF_RENDER_TOBECONTINUED do
    status := FPDF_RenderPage_Continue(APage, @pause);
  FPDF_RenderPage_Close(APage);
  if (APageWidth <= 0) or (APageHeight <= 0) then
    exit;
  jobCount := 0;
  objCount := FPDFPage_CountObjects(APage);
  for i := 0 to objCount - 1 do
  begin
    pageObj := FPDFPage_GetObject(APage, i);
    if (FPDFPageObj_GetType(pageObj) = FPDF_PAGEOBJ_IMAGE) and (FPDFPageObj_GetBounds(pageObj, l, b, r, t) <> 0) and
       (FPDFPageObj_GetMatrix(pageObj, mtx) <> 0) then
    begin
      destRect := Rect(
        Round(l / APageWidth * AWidth), Round((APageHeight - t) / APageHeight * AHeight),
        Round(r / APageWidth * AWidth), Round((APageHeight - b) / APageHeight * AHeight));
      srcImageBitmap := FPDFImageObj_GetRenderedBitmap(FDocHandle, APage, pageObj);
      if srcImageBitmap <> nil then
      begin
        SetLength(AJobs, jobCount + 1);
        AJobs[jobCount].DestRect := destRect;
        AJobs[jobCount].Matrix := mtx;
        AJobs[jobCount].SrcBitmap := srcImageBitmap;
        Inc(jobCount);
      end;
    end;
  end;
end;

procedure TPdfThumbnailCache.RenderOne(AIndex: Integer);
var
  page: FPDF_PAGE;
  fpdfBitmap: FPDF_BITMAP;
  bmp: TBitmap;
  list: TList;
  w, h: Integer;
  pageWidth, pageHeight: Single;
  usedEmbeddedThumbnail: Boolean;
  jobs: TPdfThumbCompositeJobArray;
  jobIndex: Integer;
begin
  fpdfBitmap := nil;
  bmp := nil;
  usedEmbeddedThumbnail := False;
  SetLength(jobs, 0);
  while (PdfiumHighPriorityRequests > 0) and not Terminated do
    Sleep(5);
  if Terminated then
    exit;
  FPdfLock.Enter;
  try
    page := FPDF_LoadPage(FDocHandle, AIndex);
    if page = nil then
      exit;
    try
      pageWidth := FPDF_GetPageWidthF(page);
      pageHeight := FPDF_GetPageHeightF(page);
      w := FThumbnailWidth;
      if pageWidth > 0 then
        h := Round(w * pageHeight / pageWidth)
      else
        h := w;
      if h < 1 then
        h := 1;
      if FColorScheme.Enabled then
        fpdfBitmap := PrepareColorSchemeBitmap(page, w, h, pageWidth, pageHeight, jobs)
      else
      begin
        fpdfBitmap := FPDFPage_GetThumbnailAsBitmap(page);
        usedEmbeddedThumbnail := fpdfBitmap <> nil;
        if not usedEmbeddedThumbnail then
        begin
          fpdfBitmap := FPDFBitmap_CreateEx(w, h, FPDFBitmap_BGRA, nil, 0);
          if fpdfBitmap = nil then
            exit;
          FPDFBitmap_FillRect(fpdfBitmap, 0, 0, w, h, $FFFFFFFF);
          FPDF_RenderPageBitmap(fpdfBitmap, page, 0, 0, w, h, 0, FPDF_ANNOT);
        end;
      end;
    finally
      FPDF_ClosePage(page);
    end;
  finally
    FPdfLock.Leave;
  end;
  if fpdfBitmap = nil then
    exit;
  FConvertSource := fpdfBitmap;
  Synchronize(@DoConvertBitmap);
  if usedEmbeddedThumbnail and ((FConvertResult.Width <> w) or (FConvertResult.Height <> h)) then
  begin
    FResizeTargetW := w;
    FResizeTargetH := h;
    Synchronize(@DoResizeConvertedBitmap);
  end;
  bmp := FConvertResult;
  FConvertResult := nil;
  for jobIndex := 0 to High(jobs) do
  begin
    FCompositeBmp := bmp;
    FCompositeDestRect := jobs[jobIndex].DestRect;
    FCompositeSrcBitmap := jobs[jobIndex].SrcBitmap;
    FCompositeMatrix := jobs[jobIndex].Matrix;
    FCompositePageWidth := pageWidth;
    FCompositePageHeight := pageHeight;
    FCompositeJobW := w;
    FCompositeJobH := h;
    Synchronize(@DoCompositeCurrentImage);
  end;
  FPdfLock.Enter;
  try
    for jobIndex := 0 to High(jobs) do
      FPDFBitmap_Destroy(jobs[jobIndex].SrcBitmap);
    FPDFBitmap_Destroy(fpdfBitmap);
  finally
    FPdfLock.Leave;
  end;
  list := FBitmaps.LockList;
  try
    if list[AIndex] <> nil then
      TBitmap(list[AIndex]).Free;
    list[AIndex] := bmp;
  finally
    FBitmaps.UnlockList;
  end;
  QueueReady(AIndex);
end;

function TPdfThumbnailCache.GetBitmap(APageIndex: Integer): TBitmap;
var
  list: TList;
begin
  Result := nil;
  if (APageIndex < 0) or (APageIndex >= FPageCount) then
    exit;
  list := FBitmaps.LockList;
  try
    Result := TBitmap(list[APageIndex]);
  finally
    FBitmaps.UnlockList;
  end;
end;

procedure TPdfThumbnailCache.Execute;
var
  idx: Integer;
begin
  while not Terminated do
  begin
    idx := PopNextIndex;
    if idx < 0 then
      exit;
    RenderOne(idx);
  end;
end;

end.
