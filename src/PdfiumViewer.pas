unit PdfiumViewer;

{$mode objfpc}{$H+}{$inline on}

interface

uses
  Classes, SysUtils, Types, LCLType, LCLIntf, Controls, Forms, Graphics, Clipbrd, SyncObjs, ExtCtrls,
  IntfGraphics, LResources,
  PdfiumLib, PdfiumCore, PdfiumText, PdfiumLinks, PdfiumBookmarks, PdfiumRender;

const
  MAX_PIXEL_DIMENSION = 8000;
  DEFAULT_DPI = 96;
  DOUBLE_CLICK_MS = 400;
  SELECT_REDRAW_MS = 40;   // throttles selection-highlight repaints while dragging (software per-pixel blend is CPU-heavy)
  SELECT_HITTEST_MS = 16;  // throttles hit-testing while dragging (each test can block on the document's Lock during a render)
  DEFAULT_SELECTION_COLOR = clHighlight;
  DEFAULT_SELECTION_ALPHA = 110; // 0..255 (0 = invisible, 255 = opaque)
  SELECTION_SIDE_MARGIN_PX = 2;  // left/right/bottom only - top already sits at the ascender

type
  TPdfLinkClickEvent = procedure(Sender: TObject; const ALink: TPdfLink) of object;
  TPdfRenderErrorEvent = procedure(Sender: TObject; const AMessage: String) of object;
  TPdfCustomPaintEvent = procedure(Sender: TObject; ACanvas: TCanvas) of object;

  TPdfRenderReadyEvent = procedure(ABitmap: TBitmap; APageIndex: Integer; AZoom: Double; APixelW, APixelH: Integer; const AScheme: TPdfColorScheme) of object;

  { Only the most recently requested job matters - an in-flight request can
    be superseded at any time by a newer RequestRender call. }
  TPdfRenderWorker = class(TThread)
  private
    FDocHandle: FPDF_DOCUMENT;
    { Borrowed from the owning TPdfDocument.Lock - not owned/freed here. }
    FPdfLock: TCriticalSection;
    FLock: TCriticalSection;
    FEvent: TSimpleEvent;
    FHasJob: Boolean;
    FJobPage, FJobW, FJobH: Integer;
    FJobZoom: Double;
    FJobScheme: TPdfColorScheme;
    FOnReady: TPdfRenderReadyEvent;
    FConvertSource: FPDF_BITMAP;
    FConvertResult: TBitmap;
    FCompositeBmp: TBitmap;
    FCompositeDestRect: TRect;
    FCompositeSrcBitmap: FPDF_BITMAP;
    FCompositeMatrix: FS_MATRIX;
    FCompositePageWidth, FCompositePageHeight: Double;
    FCompositeJobW, FCompositeJobH: Integer;
    FCompositeInvert: Boolean;
    procedure DoConvertBitmap;
    procedure DoCompositeCurrentImage;
  protected
    procedure Execute; override;
  public
    constructor Create(ADocHandle: FPDF_DOCUMENT; APdfLock: TCriticalSection; AOnReady: TPdfRenderReadyEvent);
    destructor Destroy; override;
    procedure RequestRender(APageIndex, AWidth, AHeight: Integer; AZoom: Double; const AScheme: TPdfColorScheme);
  end;

  { Tallest ascent/descent for a given font size anywhere on the page - gives
    every line of that size the same highlight height regardless of which
    letters it happens to contain (see TPdfTextPage.GetCharBaselineY). }
  TPdfLineMetric = record
    FontSizeKey: Integer; // Round(FontSize * 100), to key on exactly without float noise
    MaxAscent: Double;
    MaxDescent: Double;
  end;

  TPdfZoomMode = (zmManual, zmFitWidth, zmFitHeight, zmFitPage);

  TPdfViewer = class(TScrollBox)
  private
    FDocument: TPdfDocument;
    FPageIndex: Integer;
    FZoom: Double;
    FZoomMin: Double;
    FZoomMax: Double;
    FZoomMode: TPdfZoomMode;
    FPageBorderColor: TColor;
    FPageShadowColor: TColor;
    FBackgroundColor: TColor;
    FSelectionColor: TColor;
    FSelectionAlpha: Byte;
    FAllowTextSelection: Boolean;
    FCenterHorizontally: Boolean;
    FCenterVertically: Boolean;
    FOnPageChanged: TNotifyEvent;
    FOnZoomChanged: TNotifyEvent;
    FOnTextSelected: TNotifyEvent;
    FOnLinkClick: TPdfLinkClickEvent;
    FOnLinkEnter: TPdfLinkClickEvent;
    FOnLinkLeave: TPdfLinkClickEvent;
    FOnRenderError: TPdfRenderErrorEvent;
    FOnAfterPaint: TPdfCustomPaintEvent;

    FColorScheme: TPdfColorScheme;

    FPaintBox: TPaintBox;
    FWorker: TPdfRenderWorker;
    FCachedBitmap: TBitmap;
    FCachedPageIndex: Integer;
    FCachedZoom: Double;
    FCachedPixelW, FCachedPixelH: Integer;
    FCachedScheme: TPdfColorScheme;

    FLinkList: TPdfLinkList;
    FLinkListPageIndex: Integer;
    FHoveredLinkIndex: Integer;

    FTextPage: TPdfTextPage;
    FTextPageIndex: Integer;
    FLineMetrics: array of TPdfLineMetric;
    FSelection: TPdfSelection;
    FSelectionAnchor: Integer;
    FSelecting: Boolean;
    FShownStart: Integer;
    FShownCount: Integer;
    FLastRedraw: QWord;
    FLastHitTest: QWord;
    FLastClickTime: QWord;
    FLastClickCount: Integer;

    procedure SetDocument(AValue: TPdfDocument);
    procedure SetPageIndex(AValue: Integer);
    procedure SetZoom(AValue: Double);
    procedure SetCenterHorizontally(AValue: Boolean);
    procedure SetCenterVertically(AValue: Boolean);
    procedure SetBackgroundColor(AValue: TColor);
    procedure SetPageBorderColor(AValue: TColor);
    procedure SetPageShadowColor(AValue: TColor);
    procedure SetSelectionColor(AValue: TColor);
    procedure SetSelectionAlpha(AValue: Byte);
    procedure SetUseColorScheme(AValue: Boolean);
    procedure SetSchemePathFillColor(AValue: TColor);
    procedure SetSchemePathStrokeColor(AValue: TColor);
    procedure SetSchemeTextFillColor(AValue: TColor);
    procedure SetSchemeTextStrokeColor(AValue: TColor);
    procedure SetSchemeBackgroundColor(AValue: TColor);
    procedure SetInvertImageColors(AValue: Boolean);
    function GetSelectedText: String;
    function CurrentPixelSize(out APixelW, APixelH: Integer): Boolean;
    procedure RequestRenderIfNeeded;
    procedure HandleRenderReady(ABitmap: TBitmap; APageIndex: Integer; AZoom: Double; APixelW, APixelH: Integer; const AScheme: TPdfColorScheme);
    function EnsureTextPageForCurrentPage: TPdfTextPage;
    function EnsureLinksForCurrentPage: TPdfLinkList;
    function LinkIndexAtPoint(APdfX, APdfY: Double): Integer;
    procedure BuildLineMetrics;
    function LineMetricFor(AFontSize: Double; out AAscent, ADescent: Double): Boolean;
    procedure ExtendSelectionTo(AX, AY: Integer; AForce: Boolean);
    function DeviceToPagePoint(AX, AY: Integer; out APdfX, APdfY: Double): Boolean;
    function DPIScale: Double;
    procedure DrawSelectionHighlight;
    procedure UpdatePaintBoxSize;
    procedure PaintBoxPaint(Sender: TObject);
    procedure PaintBoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxMouseLeave(Sender: TObject);
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure Resize; override;
    procedure SetCursor(Value: TCursor); override;
    { Hidden - setting the inherited Color directly would desync it from FBackgroundColor. }
    property Color;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure ZoomToFitWidth;
    procedure ZoomToFitHeight;
    procedure ZoomToFitPage;
    procedure ZoomToActualSize;
    procedure ZoomIn(AStep: Double = 0.25);
    procedure ZoomOut(AStep: Double = 0.25);

    procedure GotoPage(AIndex: Integer);
    procedure GotoBookmark(ABookmark: TPdfBookmark);

    { Call after changing TPdfPage/TPdfDocument content from outside the
      viewer (SetRotation, MovePages, ...) - it has no way to notice such a
      change on its own. Does not touch TPdfThumbnailPanel. }
    procedure RefreshPage;

    procedure CopySelectionToClipboard;
    procedure SelectAll;
    procedure ClearSelection;

    { Indices are in TPdfTextPage's own character space, not a Pascal
      string's - never derive these via Pos on ExtractAllText. }
    procedure SelectTextRange(AStartIndex, ACount: Integer);

    function PageRectToClient(const APdfRect: TRectF): TRect;
  public
    property ZoomMode: TPdfZoomMode read FZoomMode;
  published
    property Document: TPdfDocument read FDocument write SetDocument;
    property PageIndex: Integer read FPageIndex write SetPageIndex default 0;
    property Zoom: Double read FZoom write SetZoom;
    property ZoomMin: Double read FZoomMin write FZoomMin;
    property ZoomMax: Double read FZoomMax write FZoomMax;
    property PageBorderColor: TColor read FPageBorderColor write SetPageBorderColor default clGray;
    property PageShadowColor: TColor read FPageShadowColor write SetPageShadowColor default clDkGray;
    property BackgroundColor: TColor read FBackgroundColor write SetBackgroundColor default $00B2B2B2;
    property SelectionColor: TColor read FSelectionColor write SetSelectionColor default DEFAULT_SELECTION_COLOR;
    property SelectionAlpha: Byte read FSelectionAlpha write SetSelectionAlpha default DEFAULT_SELECTION_ALPHA;
    property AllowTextSelection: Boolean read FAllowTextSelection write FAllowTextSelection default True;
    { Text selection, link hit-testing and click/hover events are entirely
      unaffected - they work against the page's real PDF content, never the
      rendered bitmap's colors. }
    property UseColorScheme: Boolean read FColorScheme.Enabled write SetUseColorScheme default False;
    property SchemePathFillColor: TColor read FColorScheme.PathFillColor write SetSchemePathFillColor default clSilver;
    property SchemePathStrokeColor: TColor read FColorScheme.PathStrokeColor write SetSchemePathStrokeColor default clSilver;
    property SchemeTextFillColor: TColor read FColorScheme.TextFillColor write SetSchemeTextFillColor default clWhite;
    property SchemeTextStrokeColor: TColor read FColorScheme.TextStrokeColor write SetSchemeTextStrokeColor default clWhite;
    property SchemeBackgroundColor: TColor read FColorScheme.BackgroundColor write SetSchemeBackgroundColor default $00202020;
    { Independent of UseColorScheme. Extraction (PdfiumImages.pas) always
      returns unmodified pixels regardless of this property.

      EXPERIMENTAL: an object drawn ON TOP of an image in the original
      document (e.g. a decorative border) gets silently painted over, since
      this repaints the image's own placement area with no awareness of
      anything else drawn in the same spot. }
    property InvertImageColors: Boolean read FColorScheme.InvertImages write SetInvertImageColors default False;
    property CenterHorizontally: Boolean read FCenterHorizontally write SetCenterHorizontally default False;
    property CenterVertically: Boolean read FCenterVertically write SetCenterVertically default False;
    property SelectedText: String read GetSelectedText;
    property OnPageChanged: TNotifyEvent read FOnPageChanged write FOnPageChanged;
    property OnZoomChanged: TNotifyEvent read FOnZoomChanged write FOnZoomChanged;
    property OnTextSelected: TNotifyEvent read FOnTextSelected write FOnTextSelected;
    property OnLinkClick: TPdfLinkClickEvent read FOnLinkClick write FOnLinkClick;
    property OnLinkEnter: TPdfLinkClickEvent read FOnLinkEnter write FOnLinkEnter;
    property OnLinkLeave: TPdfLinkClickEvent read FOnLinkLeave write FOnLinkLeave;
    property OnRenderError: TPdfRenderErrorEvent read FOnRenderError write FOnRenderError;
    property OnAfterPaint: TPdfCustomPaintEvent read FOnAfterPaint write FOnAfterPaint;
    property Align;
    property Anchors;
    property BorderSpacing;
    property TabOrder;
    property TabStop;
    property Visible;
    property Enabled;
  end;

procedure Register;

implementation

type
  TRenderReadyNotifier = class
  private
    FWorker: TPdfRenderWorker;
    FBitmap: TBitmap;
    FPageIndex: Integer;
    FZoom: Double;
    FPixelW, FPixelH: Integer;
    FScheme: TPdfColorScheme;
  public
    constructor Create(AWorker: TPdfRenderWorker; ABitmap: TBitmap; APageIndex: Integer; AZoom: Double; APixelW, APixelH: Integer;
      const AScheme: TPdfColorScheme);
    procedure Notify;
  end;

constructor TRenderReadyNotifier.Create(AWorker: TPdfRenderWorker; ABitmap: TBitmap; APageIndex: Integer; AZoom: Double; APixelW, APixelH: Integer;
  const AScheme: TPdfColorScheme);
begin
  inherited Create;
  FWorker := AWorker;
  FBitmap := ABitmap;
  FPageIndex := APageIndex;
  FZoom := AZoom;
  FPixelW := APixelW;
  FPixelH := APixelH;
  FScheme := AScheme;
end;

procedure TRenderReadyNotifier.Notify;
begin
  if Assigned(FWorker.FOnReady) then
    FWorker.FOnReady(FBitmap, FPageIndex, FZoom, FPixelW, FPixelH, FScheme)
  else
    FBitmap.Free;
  Free;
end;

function ColorSchemeEquals(const A, B: TPdfColorScheme): Boolean;
begin
  if A.InvertImages <> B.InvertImages then
  begin
    Result := False;
    exit;
  end;
  Result := A.Enabled = B.Enabled;
  if not Result or not A.Enabled then
    exit;
  Result := (A.PathFillColor = B.PathFillColor) and (A.PathStrokeColor = B.PathStrokeColor) and
    (A.TextFillColor = B.TextFillColor) and (A.TextStrokeColor = B.TextStrokeColor) and
    (A.BackgroundColor = B.BackgroundColor);
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
function ViewerNeverPause(pThis: Pointer): FPDF_BOOL; cdecl;
begin
  Result := 0;
end;

{ TPdfRenderWorker }

constructor TPdfRenderWorker.Create(ADocHandle: FPDF_DOCUMENT; APdfLock: TCriticalSection; AOnReady: TPdfRenderReadyEvent);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FDocHandle := ADocHandle;
  FPdfLock := APdfLock;
  FOnReady := AOnReady;
  FLock := TCriticalSection.Create;
  FEvent := TSimpleEvent.Create;
  Start;
end;

destructor TPdfRenderWorker.Destroy;
begin
  Terminate;
  FEvent.SetEvent;
  WaitFor;
  FEvent.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TPdfRenderWorker.RequestRender(APageIndex, AWidth, AHeight: Integer; AZoom: Double; const AScheme: TPdfColorScheme);
begin
  FLock.Enter;
  try
    FJobPage := APageIndex;
    FJobW := AWidth;
    FJobH := AHeight;
    FJobZoom := AZoom;
    FJobScheme := AScheme;
    FHasJob := True;
  finally
    FLock.Leave;
  end;
  FEvent.SetEvent;
end;

procedure TPdfRenderWorker.DoConvertBitmap;
begin
  FPdfLock.Enter;
  try
    FConvertResult := PdfiumBitmapToTBitmap(FConvertSource);
  finally
    FPdfLock.Leave;
  end;
end;

procedure TPdfRenderWorker.DoCompositeCurrentImage;
begin
  FPdfLock.Enter;
  try
    CompositeImagePixels(FCompositeBmp, FCompositeDestRect, FCompositeSrcBitmap, FCompositeMatrix,
      FCompositePageWidth, FCompositePageHeight, FCompositeJobW, FCompositeJobH, FCompositeInvert);
  finally
    FPdfLock.Leave;
  end;
end;

procedure TPdfRenderWorker.Execute;
type
  TCompositeJob = record
    DestRect: TRect;
    Matrix: FS_MATRIX;
    SrcBitmap: FPDF_BITMAP;
  end;
var
  page: FPDF_PAGE;
  fpdfBitmap: FPDF_BITMAP;
  bmp: TBitmap;
  jobPage, jobW, jobH: Integer;
  jobZoom: Double;
  jobScheme: TPdfColorScheme;
  scheme: FPDF_COLORSCHEME;
  pause: IFSDK_PAUSE;
  status: Integer;
  notifier: TRenderReadyNotifier;
  destRect: TRect;
  srcImageBitmap: FPDF_BITMAP;
  i, objCount, jobCount: Integer;
  pageObj: FPDF_PAGEOBJECT;
  pageWidth, pageHeight: Single;
  l, b, r, t: Single;
  mtx: FS_MATRIX;
  jobs: array of TCompositeJob;
  jobIndex: Integer;
begin
  while not Terminated do
  begin
    FEvent.WaitFor(INFINITE);
    if Terminated then
      exit;
    FLock.Enter;
    try
      if not FHasJob then
      begin
        FEvent.ResetEvent;
        continue;
      end;
      jobPage := FJobPage;
      jobW := FJobW;
      jobH := FJobH;
      jobZoom := FJobZoom;
      jobScheme := FJobScheme;
      FHasJob := False;
      FEvent.ResetEvent;
    finally
      FLock.Leave;
    end;
    bmp := nil;
    fpdfBitmap := nil;
    SetLength(jobs, 0);
    InterlockedIncrement(PdfiumHighPriorityRequests);
    try
      FPdfLock.Enter;
      try
        page := FPDF_LoadPage(FDocHandle, jobPage);
        if page = nil then
          continue;
        try
          fpdfBitmap := FPDFBitmap_CreateEx(jobW, jobH, FPDFBitmap_BGRA, nil, 0);
          if fpdfBitmap = nil then
            continue;
          if jobScheme.Enabled then
          begin
            scheme.path_fill_color := ColorToArgb(jobScheme.PathFillColor);
            scheme.path_stroke_color := ColorToArgb(jobScheme.PathStrokeColor);
            scheme.text_fill_color := ColorToArgb(jobScheme.TextFillColor);
            scheme.text_stroke_color := ColorToArgb(jobScheme.TextStrokeColor);
            pause.version := 1;
            pause.NeedToPauseNow := @ViewerNeverPause;
            pause.user := nil;
            FPDFBitmap_FillRect(fpdfBitmap, 0, 0, jobW, jobH, ColorToArgb(jobScheme.BackgroundColor));
            status := FPDF_RenderPageBitmapWithColorScheme_Start(fpdfBitmap, page, 0, 0, jobW, jobH, 0, FPDF_ANNOT, @scheme, @pause);
            while status = FPDF_RENDER_TOBECONTINUED do
              status := FPDF_RenderPage_Continue(page, @pause);
            FPDF_RenderPage_Close(page);
          end
          else
          begin
            FPDFBitmap_FillRect(fpdfBitmap, 0, 0, jobW, jobH, $FFFFFFFF);
            FPDF_RenderPageBitmap(fpdfBitmap, page, 0, 0, jobW, jobH, 0, FPDF_ANNOT);
          end;
          if jobScheme.Enabled or jobScheme.InvertImages then
          begin
            pageWidth := FPDF_GetPageWidthF(page);
            pageHeight := FPDF_GetPageHeightF(page);
            if (pageWidth > 0) and (pageHeight > 0) then
            begin
              jobCount := 0;
              objCount := FPDFPage_CountObjects(page);
              for i := 0 to objCount - 1 do
              begin
                pageObj := FPDFPage_GetObject(page, i);
                if (FPDFPageObj_GetType(pageObj) = FPDF_PAGEOBJ_IMAGE) and (FPDFPageObj_GetBounds(pageObj, l, b, r, t) <> 0) and
                   (FPDFPageObj_GetMatrix(pageObj, mtx) <> 0) then
                begin
                  destRect := Rect(
                    Round(l / pageWidth * jobW), Round((pageHeight - t) / pageHeight * jobH),
                    Round(r / pageWidth * jobW), Round((pageHeight - b) / pageHeight * jobH));
                  srcImageBitmap := FPDFImageObj_GetRenderedBitmap(FDocHandle, page, pageObj);
                  if srcImageBitmap <> nil then
                  begin
                    SetLength(jobs, jobCount + 1);
                    jobs[jobCount].DestRect := destRect;
                    jobs[jobCount].Matrix := mtx;
                    jobs[jobCount].SrcBitmap := srcImageBitmap;
                    Inc(jobCount);
                  end;
                end;
              end;
            end;
          end;
        finally
          FPDF_ClosePage(page);
        end;
      finally
        FPdfLock.Leave;
      end;
    finally
      InterlockedDecrement(PdfiumHighPriorityRequests);
    end;

    if (fpdfBitmap <> nil) and not Terminated then
    begin
      try
        FConvertSource := fpdfBitmap;
        Synchronize(@DoConvertBitmap);
        bmp := FConvertResult;
        FConvertResult := nil;
        if bmp <> nil then
        begin
          for jobIndex := 0 to High(jobs) do
          begin
            FCompositeBmp := bmp;
            FCompositeDestRect := jobs[jobIndex].DestRect;
            FCompositeSrcBitmap := jobs[jobIndex].SrcBitmap;
            FCompositeMatrix := jobs[jobIndex].Matrix;
            FCompositePageWidth := pageWidth;
            FCompositePageHeight := pageHeight;
            FCompositeJobW := jobW;
            FCompositeJobH := jobH;
            FCompositeInvert := jobScheme.InvertImages;
            Synchronize(@DoCompositeCurrentImage);
          end;
        end;
      finally
        FPdfLock.Enter;
        try
          for jobIndex := 0 to High(jobs) do
            FPDFBitmap_Destroy(jobs[jobIndex].SrcBitmap);
          FPDFBitmap_Destroy(fpdfBitmap);
        finally
          FPdfLock.Leave;
        end;
      end;
    end
    else if fpdfBitmap <> nil then
    begin
      FPdfLock.Enter;
      try
        FPDFBitmap_Destroy(fpdfBitmap);
      finally
        FPdfLock.Leave;
      end;
    end;
    if (bmp <> nil) and not Terminated then
    begin
      notifier := TRenderReadyNotifier.Create(Self, bmp, jobPage, jobZoom, jobW, jobH, jobScheme);
      Queue(@notifier.Notify);
    end
    else if bmp <> nil then
      bmp.Free;
  end;
end;

{ TPdfViewer }

constructor TPdfViewer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  DoubleBuffered := True; // otherwise resizing FPaintBox flashes its background color before OnPaint runs
  AutoScroll := True;
  FZoom := 1.0;
  FZoomMin := 0.1;
  FZoomMax := 10.0;
  FPageBorderColor := clGray;
  FPageShadowColor := clDkGray;
  FBackgroundColor := $00B2B2B2;
  FSelectionColor := DEFAULT_SELECTION_COLOR;
  FSelectionAlpha := DEFAULT_SELECTION_ALPHA;
  FAllowTextSelection := True;
  FZoomMode := zmManual;
  FCenterHorizontally := False;
  FCenterVertically := False;
  FColorScheme.Enabled := False;
  FColorScheme.PathFillColor := clSilver;
  FColorScheme.PathStrokeColor := clSilver;
  FColorScheme.TextFillColor := clWhite;
  FColorScheme.TextStrokeColor := clWhite;
  FColorScheme.BackgroundColor := $00202020;
  FColorScheme.InvertImages := False;
  FCachedPageIndex := -1;
  FTextPageIndex := -1;
  FLinkListPageIndex := -1;
  FHoveredLinkIndex := -1;
  FSelectionAnchor := -1;
  FShownStart := -1;
  FShownCount := 0;
  FLastRedraw := 0;
  Color := FBackgroundColor;
  FPaintBox := TPaintBox.Create(Self);
  FPaintBox.Parent := Self;
  FPaintBox.Left := 0;
  FPaintBox.Top := 0;
  FPaintBox.Width := 1;
  FPaintBox.Height := 1;
  FPaintBox.OnPaint := @PaintBoxPaint;
  FPaintBox.OnMouseDown := @PaintBoxMouseDown;
  FPaintBox.OnMouseMove := @PaintBoxMouseMove;
  FPaintBox.OnMouseUp := @PaintBoxMouseUp;
  FPaintBox.OnMouseLeave := @PaintBoxMouseLeave;
end;

destructor TPdfViewer.Destroy;
begin
  FreeAndNil(FWorker);
  FreeAndNil(FCachedBitmap);
  FreeAndNil(FSelection);
  FreeAndNil(FTextPage);
  FreeAndNil(FLinkList);
  inherited Destroy;
end;

function TPdfViewer.DPIScale: Double;
begin
  Result := DEFAULT_DPI / 72;
end;

procedure TPdfViewer.SetDocument(AValue: TPdfDocument);
begin
  if FDocument = AValue then
    exit;
  FreeAndNil(FWorker);
  FreeAndNil(FCachedBitmap);
  FreeAndNil(FSelection);
  FreeAndNil(FTextPage);
  FreeAndNil(FLinkList);
  FTextPageIndex := -1;
  FCachedPageIndex := -1;
  FLinkListPageIndex := -1;
  FHoveredLinkIndex := -1;
  FDocument := AValue;
  FPageIndex := 0;
  if FDocument <> nil then
  begin
    FWorker := TPdfRenderWorker.Create(FDocument.Handle, FDocument.Lock, @HandleRenderReady);
    EnsureTextPageForCurrentPage; // already (re)creates FSelection too - do not also construct one here, it would leak
  end;
  UpdatePaintBoxSize;
  FPaintBox.Invalidate;
  if Assigned(FOnPageChanged) then
    FOnPageChanged(Self);
end;

procedure TPdfViewer.SetPageIndex(AValue: Integer);
begin
  if FDocument = nil then
    exit;
  if AValue < 0 then
    AValue := 0;
  if AValue >= FDocument.PageCount then
    AValue := FDocument.PageCount - 1;
  if AValue = FPageIndex then
    exit;
  FPageIndex := AValue;
  ClearSelection;
  FHoveredLinkIndex := -1; // would otherwise point at an unrelated link on the new page
  UpdatePaintBoxSize;
  { GotoBookmark relies on this reset: it leaves the scroll position alone
    when the bookmark has no vertical coordinate, which is only "top"
    because this already ran first. }
  VertScrollBar.Position := 0;
  HorzScrollBar.Position := 0;
  FPaintBox.Invalidate;
  if Assigned(FOnPageChanged) then
    FOnPageChanged(Self);
end;

procedure TPdfViewer.SetZoom(AValue: Double);
begin
  { Any direct zoom change counts as manual; ZoomToFitWidth/FitHeight/FitPage
    each set FZoomMode back to their own value right after calling this
    setter, so a Fit* call still ends up correctly tagged. }
  FZoomMode := zmManual;
  if AValue < FZoomMin then
    AValue := FZoomMin;
  if AValue > FZoomMax then
    AValue := FZoomMax;
  if Abs(AValue - FZoom) < 1e-6 then
    exit;
  FZoom := AValue;
  UpdatePaintBoxSize;
  FPaintBox.Invalidate;
  if Assigned(FOnZoomChanged) then
    FOnZoomChanged(Self);
end;

function TPdfViewer.GetSelectedText: String;
begin
  if FSelection <> nil then
    Result := FSelection.SelectedText
  else
    Result := '';
end;

function TPdfViewer.EnsureTextPageForCurrentPage: TPdfTextPage;
var
  page: TPdfPage;
begin
  if FDocument = nil then
  begin
    Result := nil;
    exit;
  end;
  if FTextPageIndex <> FPageIndex then
  begin
    FreeAndNil(FTextPage);
    page := FDocument.Pages[FPageIndex];
    FTextPage := TPdfTextPage.Create(page);
    FTextPageIndex := FPageIndex;
    FreeAndNil(FSelection);
    FSelection := TPdfSelection.Create(FTextPage);
    BuildLineMetrics;
  end;
  Result := FTextPage;
end;

function TPdfViewer.EnsureLinksForCurrentPage: TPdfLinkList;
begin
  if FDocument = nil then
  begin
    Result := nil;
    exit;
  end;
  if FLinkListPageIndex <> FPageIndex then
  begin
    FreeAndNil(FLinkList);
    FLinkList := TPdfLinkList.Create(FDocument.Pages[FPageIndex]);
    FLinkListPageIndex := FPageIndex;
  end;
  Result := FLinkList;
end;

function TPdfViewer.LinkIndexAtPoint(APdfX, APdfY: Double): Integer;
var
  links: TPdfLinkList;
  i: Integer;
  link: TPdfLink;
begin
  Result := -1;
  links := EnsureLinksForCurrentPage;
  if links = nil then
    exit;
  for i := 0 to links.Count - 1 do
  begin
    link := links[i];
    if (APdfX >= link.Bounds.Left) and (APdfX <= link.Bounds.Right) and
       (APdfY >= link.Bounds.Bottom) and (APdfY <= link.Bounds.Top) then
    begin
      Result := i;
      exit;
    end;
  end;
end;

procedure TPdfViewer.BuildLineMetrics;
var
  i, key, m: Integer;
  ci: TPdfCharInfo;
  baseY, ascent, descent: Double;
  found: Boolean;
begin
  SetLength(FLineMetrics, 0);
  if FTextPage = nil then
    exit;
  for i := 0 to FTextPage.CharCount - 1 do
  begin
    ci := FTextPage.Characters[i];
    if (ci.Bounds.Right <= ci.Bounds.Left) and (ci.Bounds.Top <= ci.Bounds.Bottom) then // space/control: degenerate zero-area box
      continue;
    baseY := FTextPage.GetCharBaselineY(i);
    ascent := ci.Bounds.Top - baseY;
    descent := baseY - ci.Bounds.Bottom;
    key := Round(ci.FontSize * 100);
    found := False;
    for m := 0 to High(FLineMetrics) do
    begin
      if FLineMetrics[m].FontSizeKey = key then
      begin
        if ascent > FLineMetrics[m].MaxAscent then
          FLineMetrics[m].MaxAscent := ascent;
        if descent > FLineMetrics[m].MaxDescent then
          FLineMetrics[m].MaxDescent := descent;
        found := True;
        break;
      end;
    end;
    if not found then
    begin
      SetLength(FLineMetrics, Length(FLineMetrics) + 1);
      FLineMetrics[High(FLineMetrics)].FontSizeKey := key;
      FLineMetrics[High(FLineMetrics)].MaxAscent := ascent;
      FLineMetrics[High(FLineMetrics)].MaxDescent := descent;
    end;
  end;
end;

function TPdfViewer.LineMetricFor(AFontSize: Double; out AAscent, ADescent: Double): Boolean;
var
  key, m: Integer;
begin
  key := Round(AFontSize * 100);
  for m := 0 to High(FLineMetrics) do
    if FLineMetrics[m].FontSizeKey = key then
    begin
      AAscent := FLineMetrics[m].MaxAscent;
      ADescent := FLineMetrics[m].MaxDescent;
      Result := True;
      exit;
    end;
  Result := False;
end;

function TPdfViewer.CurrentPixelSize(out APixelW, APixelH: Integer): Boolean;
var
  page: TPdfPage;
begin
  Result := False;
  if FDocument = nil then
    exit;
  page := FDocument.Pages[FPageIndex];
  APixelW := Round(page.Width * FZoom * DPIScale);
  APixelH := Round(page.Height * FZoom * DPIScale);
  if APixelW < 1 then
    APixelW := 1;
  if APixelH < 1 then
    APixelH := 1;
  if APixelW > MAX_PIXEL_DIMENSION then
    APixelW := MAX_PIXEL_DIMENSION;
  if APixelH > MAX_PIXEL_DIMENSION then
    APixelH := MAX_PIXEL_DIMENSION;
  Result := True;
end;

procedure TPdfViewer.UpdatePaintBoxSize;
var
  w, h: Integer;
begin
  if not CurrentPixelSize(w, h) then
  begin
    FPaintBox.Width := 1;
    FPaintBox.Height := 1;
    FPaintBox.Left := 0;
    FPaintBox.Top := 0;
    exit;
  end;
  FPaintBox.Width := w;
  FPaintBox.Height := h;
  if FCenterHorizontally and (w < ClientWidth) then
    FPaintBox.Left := (ClientWidth - w) div 2
  else
    FPaintBox.Left := 0;
  if FCenterVertically and (h < ClientHeight) then
    FPaintBox.Top := (ClientHeight - h) div 2
  else
    FPaintBox.Top := 0;
end;

procedure TPdfViewer.SetCenterHorizontally(AValue: Boolean);
begin
  if FCenterHorizontally = AValue then
    exit;
  FCenterHorizontally := AValue;
  UpdatePaintBoxSize;
end;

procedure TPdfViewer.SetCenterVertically(AValue: Boolean);
begin
  if FCenterVertically = AValue then
    exit;
  FCenterVertically := AValue;
  UpdatePaintBoxSize;
end;

procedure TPdfViewer.SetBackgroundColor(AValue: TColor);
begin
  if FBackgroundColor = AValue then
    exit;
  FBackgroundColor := AValue;
  Color := FBackgroundColor;
end;

procedure TPdfViewer.SetPageBorderColor(AValue: TColor);
begin
  if FPageBorderColor = AValue then
    exit;
  FPageBorderColor := AValue;
  FPaintBox.Invalidate;
end;

procedure TPdfViewer.SetPageShadowColor(AValue: TColor);
begin
  if FPageShadowColor = AValue then
    exit;
  FPageShadowColor := AValue;
  FPaintBox.Invalidate;
end;

procedure TPdfViewer.SetSelectionColor(AValue: TColor);
begin
  if FSelectionColor = AValue then
    exit;
  FSelectionColor := AValue;
  FPaintBox.Invalidate;
end;

procedure TPdfViewer.SetSelectionAlpha(AValue: Byte);
begin
  if FSelectionAlpha = AValue then
    exit;
  FSelectionAlpha := AValue;
  FPaintBox.Invalidate;
end;

procedure TPdfViewer.SetUseColorScheme(AValue: Boolean);
begin
  if FColorScheme.Enabled = AValue then
    exit;
  FColorScheme.Enabled := AValue;
  FPaintBox.Invalidate;
end;

procedure TPdfViewer.SetSchemePathFillColor(AValue: TColor);
begin
  if FColorScheme.PathFillColor = AValue then
    exit;
  FColorScheme.PathFillColor := AValue;
  FPaintBox.Invalidate;
end;

procedure TPdfViewer.SetSchemePathStrokeColor(AValue: TColor);
begin
  if FColorScheme.PathStrokeColor = AValue then
    exit;
  FColorScheme.PathStrokeColor := AValue;
  FPaintBox.Invalidate;
end;

procedure TPdfViewer.SetSchemeTextFillColor(AValue: TColor);
begin
  if FColorScheme.TextFillColor = AValue then
    exit;
  FColorScheme.TextFillColor := AValue;
  FPaintBox.Invalidate;
end;

procedure TPdfViewer.SetSchemeTextStrokeColor(AValue: TColor);
begin
  if FColorScheme.TextStrokeColor = AValue then
    exit;
  FColorScheme.TextStrokeColor := AValue;
  FPaintBox.Invalidate;
end;

procedure TPdfViewer.SetSchemeBackgroundColor(AValue: TColor);
begin
  if FColorScheme.BackgroundColor = AValue then
    exit;
  FColorScheme.BackgroundColor := AValue;
  FPaintBox.Invalidate;
end;

procedure TPdfViewer.SetInvertImageColors(AValue: Boolean);
begin
  if FColorScheme.InvertImages = AValue then
    exit;
  FColorScheme.InvertImages := AValue;
  FPaintBox.Invalidate;
end;

procedure TPdfViewer.Resize;
begin
  inherited Resize;
  { TScrollBox's own constructor can trigger a Resize before ours has
    created FPaintBox yet (virtual dispatch runs this override even
    mid-ancestor-constructor). }
  if FPaintBox = nil then
    exit;
  if FDocument <> nil then
    case FZoomMode of
      zmFitWidth: ZoomToFitWidth;
      zmFitHeight: ZoomToFitHeight;
      zmFitPage: ZoomToFitPage;
    end;
  UpdatePaintBoxSize;
end;

{ FPaintBox sits under the mouse for the whole visible page area, so the OS
  asks it, not the TScrollBox, which cursor to show - forward it. }
procedure TPdfViewer.SetCursor(Value: TCursor);
begin
  inherited SetCursor(Value);
  if FPaintBox <> nil then
    FPaintBox.Cursor := Value;
end;

procedure TPdfViewer.RequestRenderIfNeeded;
var
  w, h: Integer;
begin
  if (FDocument = nil) or (FWorker = nil) then
    exit;
  if not CurrentPixelSize(w, h) then
    exit;
  if (FCachedBitmap <> nil) and (FCachedPageIndex = FPageIndex) and
     (Abs(FCachedZoom - FZoom) < 1e-6) and (FCachedPixelW = w) and (FCachedPixelH = h) and
     ColorSchemeEquals(FCachedScheme, FColorScheme) then
    exit;
  FWorker.RequestRender(FPageIndex, w, h, FZoom, FColorScheme);
end;

procedure TPdfViewer.HandleRenderReady(ABitmap: TBitmap; APageIndex: Integer; AZoom: Double; APixelW, APixelH: Integer; const AScheme: TPdfColorScheme);
begin
  if (APageIndex <> FPageIndex) or (Abs(AZoom - FZoom) > 1e-6) or not ColorSchemeEquals(AScheme, FColorScheme) then
  begin
    { Superseded by a newer request while this one was in flight. }
    ABitmap.Free;
    exit;
  end;
  FreeAndNil(FCachedBitmap);
  FCachedBitmap := ABitmap;
  FCachedPageIndex := APageIndex;
  FCachedZoom := AZoom;
  FCachedPixelW := APixelW;
  FCachedPixelH := APixelH;
  FCachedScheme := AScheme;
  FPaintBox.Invalidate;
end;

procedure TPdfViewer.PaintBoxPaint(Sender: TObject);
var
  destRect: TRect;
  w, h: Integer;
begin
  if not CurrentPixelSize(w, h) then
    exit;

  destRect := Rect(0, 0, w, h);
  if (FCachedBitmap <> nil) and (FCachedPageIndex = FPageIndex) and
     (Abs(FCachedZoom - FZoom) < 1e-6) and (FCachedPixelW = w) and (FCachedPixelH = h) and
     ColorSchemeEquals(FCachedScheme, FColorScheme) then
    FPaintBox.Canvas.Draw(0, 0, FCachedBitmap)
  else
  begin
    { Deliberately keep showing the stale bitmap, not a blank fill, while the new one renders. }
    if FCachedBitmap <> nil then
    begin
      if (FCachedBitmap.Width = w) and (FCachedBitmap.Height = h) then
        FPaintBox.Canvas.Draw(0, 0, FCachedBitmap)
      else
        FPaintBox.Canvas.StretchDraw(destRect, FCachedBitmap);
    end
    else
    begin
      if FColorScheme.Enabled then
        FPaintBox.Canvas.Brush.Color := FColorScheme.BackgroundColor
      else
        FPaintBox.Canvas.Brush.Color := clWhite;
      FPaintBox.Canvas.FillRect(destRect);
    end;
    RequestRenderIfNeeded;
  end;
  FPaintBox.Canvas.Pen.Color := FPageBorderColor;
  FPaintBox.Canvas.Brush.Style := bsClear;
  FPaintBox.Canvas.Rectangle(destRect);
  FPaintBox.Canvas.Brush.Style := bsSolid;
  DrawSelectionHighlight;
  if Assigned(FOnAfterPaint) then
    FOnAfterPaint(Self, FPaintBox.Canvas);
end;

{ ASource must be a stable, in-memory bitmap (the rendered page), not the
  live/scrolled widget canvas, or the highlight can tint the wrong pixels. }
procedure AlphaBlendRect(const ASource, ADest: TCanvas; const ARect: TRect; AColor: TColor; AAlpha: Byte);
var
  w, h, x, y: Integer;
  temp: TBitmap;
  img: TLazIntfImage;
  row: PByte;
  hb, hg, hr: Byte;
begin
  w := ARect.Right - ARect.Left;
  h := ARect.Bottom - ARect.Top;
  if (w <= 0) or (h <= 0) then
    exit;
  AColor := ColorToRGB(AColor);
  hb := (AColor shr 16) and $FF;
  hg := (AColor shr 8) and $FF;
  hr := AColor and $FF;
  temp := TBitmap.Create;
  try
    temp.PixelFormat := pf32bit;
    temp.SetSize(w, h);
    temp.Canvas.CopyRect(Rect(0, 0, w, h), ASource, ARect);
    img := temp.CreateIntfImage;
    try
      for y := 0 to h - 1 do
      begin
        row := PByte(img.GetDataLineStart(y));
        for x := 0 to w - 1 do
        begin
          row[x * 4]     := (row[x * 4] * (255 - AAlpha) + hb * AAlpha) div 255;
          row[x * 4 + 1] := (row[x * 4 + 1] * (255 - AAlpha) + hg * AAlpha) div 255;
          row[x * 4 + 2] := (row[x * 4 + 2] * (255 - AAlpha) + hr * AAlpha) div 255;
        end;
      end;
      temp.LoadFromIntfImage(img);
    finally
      img.Free;
    end;

    ADest.Draw(ARect.Left, ARect.Top, temp);
  finally
    temp.Free;
  end;
end;

procedure TPdfViewer.DrawSelectionHighlight;
var
  page: TPdfPage;
  scale: Double;
  selStart, selCount, idx, n, i, j: Integer;
  ci: TPdfCharInfo;
  baseY, ascent, descent, extTop, extBottom: Double;
  px: array of TRect;
  band: TRect;
  tmp: TRect;
  curW, curH: Integer;
begin
  if (FSelection = nil) or FSelection.IsEmpty then
    exit;
  { FCachedBitmap must be the CURRENT page at the CURRENT zoom/pixel size -
    otherwise a highlight computed at the current zoom could blend onto a
    bitmap still mid-re-render, landing on the wrong pixels. }
  if (FCachedBitmap = nil) or (FCachedPageIndex <> FPageIndex) or (Abs(FCachedZoom - FZoom) > 1e-6) then
    exit;
  if not CurrentPixelSize(curW, curH) or (FCachedPixelW <> curW) or (FCachedPixelH <> curH) then
    exit;
  page := FDocument.Pages[FPageIndex];
  scale := FZoom * DPIScale;
  selStart := FSelection.StartIndex;
  selCount := FSelection.Count;
  if selCount <= 0 then
    exit;
  SetLength(px, selCount);
  n := 0;
  for idx := selStart to selStart + selCount - 1 do
  begin
    ci := FTextPage.Characters[idx];
    if (ci.Bounds.Right <= ci.Bounds.Left) and (ci.Bounds.Top <= ci.Bounds.Bottom) then
      continue;
    baseY := FTextPage.GetCharBaselineY(idx);
    if LineMetricFor(ci.FontSize, ascent, descent) then
    begin
      extTop := baseY + ascent;
      extBottom := baseY - descent;
    end
    else
    begin
      extTop := ci.Bounds.Top; // should not happen - fall back to this character's own ink box
      extBottom := ci.Bounds.Bottom;
    end;
    px[n].Left := Round(ci.Bounds.Left * scale);
    px[n].Right := Round(ci.Bounds.Right * scale);
    px[n].Top := Round((page.Height - extTop) * scale);
    px[n].Bottom := Round((page.Height - extBottom) * scale);
    Inc(n);
  end;
  if n = 0 then
    exit;
  for i := 1 to n - 1 do
  begin
    tmp := px[i];
    j := i;
    while (j > 0) and (px[j - 1].Top > tmp.Top) do
    begin
      px[j] := px[j - 1];
      Dec(j);
    end;
    px[j] := tmp;
  end;
  i := 0;
  while i < n do
  begin
    band := px[i];
    j := i + 1;
    while (j < n) and (px[j].Top <= band.Bottom) do
    begin
      if px[j].Top < band.Top then
        band.Top := px[j].Top;
      if px[j].Bottom > band.Bottom then
        band.Bottom := px[j].Bottom;
      if px[j].Left < band.Left then
        band.Left := px[j].Left;
      if px[j].Right > band.Right then
        band.Right := px[j].Right;
      Inc(j);
    end;
    band.Left := band.Left - SELECTION_SIDE_MARGIN_PX;
    band.Right := band.Right + SELECTION_SIDE_MARGIN_PX;
    band.Bottom := band.Bottom + SELECTION_SIDE_MARGIN_PX;
    AlphaBlendRect(FCachedBitmap.Canvas, FPaintBox.Canvas, band, FSelectionColor, FSelectionAlpha);
    i := j;
  end;
end;

function TPdfViewer.DeviceToPagePoint(AX, AY: Integer; out APdfX, APdfY: Double): Boolean;
var
  page: TPdfPage;
  scale: Double;
begin
  Result := False;
  if FDocument = nil then
    exit;
  page := FDocument.Pages[FPageIndex];
  scale := FZoom * DPIScale;
  if scale <= 0 then
    exit;
  APdfX := AX / scale;
  APdfY := page.Height - (AY / scale);
  Result := True;
end;

function TPdfViewer.PageRectToClient(const APdfRect: TRectF): TRect;
var
  page: TPdfPage;
  scale: Double;
begin
  Result := Rect(0, 0, 0, 0);
  if FDocument = nil then
    exit;
  page := FDocument.Pages[FPageIndex];
  scale := FZoom * DPIScale;
  Result.Left := Round(APdfRect.Left * scale);
  Result.Right := Round(APdfRect.Right * scale);
  Result.Top := Round((page.Height - APdfRect.Top) * scale);
  Result.Bottom := Round((page.Height - APdfRect.Bottom) * scale);
end;

procedure TPdfViewer.PaintBoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  pdfX, pdfY: Double;
  textPage: TPdfTextPage;
  charIdx: Integer;
  linkIdx: Integer;
  now: QWord;
  clickCount: Integer;
begin
  SetFocus;
  if FDocument = nil then
    exit;
  if Button = mbLeft then
  begin
    now := GetTickCount64;
    if (now - FLastClickTime) < DOUBLE_CLICK_MS then
      clickCount := FLastClickCount + 1
    else
      clickCount := 1;
    FLastClickTime := now;
    FLastClickCount := clickCount;
    { Link hit-testing takes priority over text selection. }
    if DeviceToPagePoint(X, Y, pdfX, pdfY) then
    begin
      linkIdx := LinkIndexAtPoint(pdfX, pdfY);
      if linkIdx >= 0 then
      begin
        if Assigned(FOnLinkClick) then
          FOnLinkClick(Self, FLinkList[linkIdx]);
        exit;
      end;
    end;
    if not FAllowTextSelection then
      exit;
    textPage := EnsureTextPageForCurrentPage;
    if textPage = nil then
      exit;
    if not DeviceToPagePoint(X, Y, pdfX, pdfY) then
      exit;
    charIdx := textPage.CharIndexAtPos(pdfX, pdfY);
    if charIdx < 0 then
    begin
      ClearSelection;
      exit;
    end;
    case clickCount of
      2: FSelection.SelectWord(charIdx);
      3: begin
           FSelection.SelectLine(charIdx);
           FLastClickCount := 0;
         end;
    else
    begin
      FSelectionAnchor := charIdx;
      FSelecting := True;
      FSelection.SelectRange(charIdx, 1);
      FShownStart := charIdx;
      FShownCount := 1;
    end;
    end;
    FPaintBox.Invalidate;
    if Assigned(FOnTextSelected) then
      FOnTextSelected(Self);
  end;
end;

{ AForce bypasses the throttles below - used only by PaintBoxMouseUp, so the
  selection always ends exactly where the mouse was released. }
procedure TPdfViewer.ExtendSelectionTo(AX, AY: Integer; AForce: Boolean);
var
  pdfX, pdfY: Double;
  textPage: TPdfTextPage;
  charIdx, startIdx, count: Integer;
  now: QWord;
begin
  textPage := FTextPage;
  if textPage = nil then
    exit;
  now := GetTickCount64;
  if not AForce and ((now - FLastHitTest) < SELECT_HITTEST_MS) then
    exit;
  FLastHitTest := now;
  if not DeviceToPagePoint(AX, AY, pdfX, pdfY) then
    exit;
  if AForce then
    charIdx := textPage.CharIndexAtPos(pdfX, pdfY)
  else
  begin
    if not textPage.Page.Document.Lock.TryEnter then
      exit;
    try
      charIdx := textPage.CharIndexAtPos(pdfX, pdfY);
    finally
      textPage.Page.Document.Lock.Leave;
    end;
  end;
  if charIdx < 0 then
    exit;
  if charIdx >= FSelectionAnchor then
  begin
    startIdx := FSelectionAnchor;
    count := charIdx - FSelectionAnchor + 1;
  end
  else
  begin
    startIdx := charIdx;
    count := FSelectionAnchor - charIdx + 1;
  end;
  if (startIdx <> FShownStart) or (count <> FShownCount) then
  begin
    FSelection.SelectRange(startIdx, count);
    FShownStart := startIdx;
    FShownCount := count;
    if AForce or ((now - FLastRedraw) >= SELECT_REDRAW_MS) then
    begin
      FLastRedraw := now;
      FPaintBox.Invalidate;
    end;
    if Assigned(FOnTextSelected) then
      FOnTextSelected(Self);
  end;
end;

procedure TPdfViewer.PaintBoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  pdfX, pdfY: Double;
  linkIdx: Integer;
begin
  if FSelecting then
    ExtendSelectionTo(X, Y, False);
  if FDocument = nil then
    exit;
  if DeviceToPagePoint(X, Y, pdfX, pdfY) then
    linkIdx := LinkIndexAtPoint(pdfX, pdfY)
  else
    linkIdx := -1;
  if linkIdx = FHoveredLinkIndex then
    exit;
  if FHoveredLinkIndex >= 0 then
    if Assigned(FOnLinkLeave) then
      FOnLinkLeave(Self, FLinkList[FHoveredLinkIndex]);
  FHoveredLinkIndex := linkIdx;
  if FHoveredLinkIndex >= 0 then
    if Assigned(FOnLinkEnter) then
      FOnLinkEnter(Self, FLinkList[FHoveredLinkIndex]);
  FPaintBox.Invalidate;
end;

{ FPaintBox has no window handle of its own (TGraphicControl), so mouse moves
  stop reaching PaintBoxMouseMove the instant the pointer leaves it - without
  this, an OnLinkEnter could go unmatched by an OnLinkLeave. }
procedure TPdfViewer.PaintBoxMouseLeave(Sender: TObject);
begin
  if FHoveredLinkIndex < 0 then
    exit;
  if Assigned(FOnLinkLeave) then
    FOnLinkLeave(Self, FLinkList[FHoveredLinkIndex]);
  FHoveredLinkIndex := -1;
  FPaintBox.Invalidate;
end;

procedure TPdfViewer.PaintBoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if FSelecting then
  begin
    ExtendSelectionTo(X, Y, True);
    FSelecting := False;
  end;
  FPaintBox.Invalidate;
end;

procedure TPdfViewer.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  if ssCtrl in Shift then
  begin
    if Key = Ord('A') then
    begin
      SelectAll;
      Key := 0;
    end
    else if Key = Ord('C') then
    begin
      CopySelectionToClipboard;
      Key := 0;
    end;
  end;
end;

procedure TPdfViewer.ZoomToFitWidth;
var
  page: TPdfPage;
  fullW, fullH, availW: Integer;
  newZoom, pixH: Double;
begin
  if FDocument = nil then
    exit;
  page := FDocument.Pages[FPageIndex];
  if page.Width > 0 then
  begin
    { ClientSizeWithoutBar, not ClientWidth/Height: those reflect scrollbars
      from the PREVIOUS zoom, not the fit being computed now, causing
      scrollbar thrashing (grow one, which eats into the width, which forces
      the other). }
    fullW := VertScrollBar.ClientSizeWithoutBar;
    fullH := HorzScrollBar.ClientSizeWithoutBar;
    newZoom := fullW / (page.Width * DPIScale);
    pixH := page.Height * newZoom * DPIScale;
    if (page.Height > 0) and (pixH > fullH) then
    begin
      availW := fullW - VertScrollBar.Size;
      if availW > 0 then
        newZoom := availW / (page.Width * DPIScale);
    end;
    Zoom := newZoom;
  end;
  FZoomMode := zmFitWidth;
end;

procedure TPdfViewer.ZoomToFitHeight;
var
  page: TPdfPage;
  fullW, fullH, availH: Integer;
  newZoom, pixW: Double;
begin
  if FDocument = nil then
    exit;
  page := FDocument.Pages[FPageIndex];
  if page.Height > 0 then
  begin
    fullW := VertScrollBar.ClientSizeWithoutBar;
    fullH := HorzScrollBar.ClientSizeWithoutBar;
    newZoom := fullH / (page.Height * DPIScale);
    pixW := page.Width * newZoom * DPIScale;
    if (page.Width > 0) and (pixW > fullW) then
    begin
      availH := fullH - HorzScrollBar.Size;
      if availH > 0 then
        newZoom := availH / (page.Height * DPIScale);
    end;
    Zoom := newZoom;
  end;
  FZoomMode := zmFitHeight;
end;

procedure TPdfViewer.ZoomToFitPage;
var
  page: TPdfPage;
  fullW, fullH: Integer;
  zw, zh: Double;
begin
  if FDocument = nil then
    exit;
  page := FDocument.Pages[FPageIndex];
  if (page.Width > 0) and (page.Height > 0) then
  begin
    { ClientSizeWithoutBar, not ClientWidth/Height, which may still be
      narrowed by a scrollbar left over from a previous zoom mode. }
    fullW := VertScrollBar.ClientSizeWithoutBar;
    fullH := HorzScrollBar.ClientSizeWithoutBar;
    zw := fullW / (page.Width * DPIScale);
    zh := fullH / (page.Height * DPIScale);
    if zw < zh then
      Zoom := zw
    else
      Zoom := zh;
  end;
  FZoomMode := zmFitPage;
end;

procedure TPdfViewer.ZoomToActualSize;
begin
  Zoom := 1.0;
end;

procedure TPdfViewer.ZoomIn(AStep: Double = 0.25);
begin
  Zoom := FZoom + AStep;
end;

procedure TPdfViewer.ZoomOut(AStep: Double = 0.25);
begin
  Zoom := FZoom - AStep;
end;

procedure TPdfViewer.GotoPage(AIndex: Integer);
begin
  PageIndex := AIndex;
end;

procedure TPdfViewer.GotoBookmark(ABookmark: TPdfBookmark);
var
  page: TPdfPage;
  pixelY: Integer;
begin
  if (ABookmark = nil) or (ABookmark.PageIndex < 0) then
    exit;
  PageIndex := ABookmark.PageIndex;
  if FDocument = nil then
    exit;
  if ABookmark.PageY <= 0 then // 0 (no vertical position set) means "top", not "scroll to raw 0"
    exit;
  page := FDocument.Pages[FPageIndex];
  pixelY := Round((page.Height - ABookmark.PageY) * FZoom * DPIScale);
  if pixelY < 0 then
    pixelY := 0;
  VertScrollBar.Position := pixelY;
end;

procedure TPdfViewer.RefreshPage;
begin
  if FDocument = nil then
    exit;
  ClearSelection;
  FHoveredLinkIndex := -1;
  { -1 never matches a real page index, forcing text/link/render caches to rebuild on next use. }
  FTextPageIndex := -1;
  FLinkListPageIndex := -1;
  FCachedPageIndex := -1;
  UpdatePaintBoxSize;
  FPaintBox.Invalidate;
end;

procedure TPdfViewer.CopySelectionToClipboard;
var
  s: String;
begin
  s := GetSelectedText;
  if s <> '' then
    Clipboard.AsText := s;
end;

procedure TPdfViewer.SelectAll;
begin
  if EnsureTextPageForCurrentPage = nil then
    exit;
  FSelection.SelectRange(0, FTextPage.CharCount);
  FShownStart := 0;
  FShownCount := FTextPage.CharCount;
  FPaintBox.Invalidate;
  if Assigned(FOnTextSelected) then
    FOnTextSelected(Self);
end;

procedure TPdfViewer.SelectTextRange(AStartIndex, ACount: Integer);
var
  bounds: TRectF;
  page: TPdfPage;
  pixelY: Integer;
begin
  if EnsureTextPageForCurrentPage = nil then
    raise EPdfiumError.Create('SelectTextRange: no document/page loaded.');
  if (AStartIndex < 0) or (ACount <= 0) or (AStartIndex + ACount > FTextPage.CharCount) then
    raise EPdfiumError.Create(Format('SelectTextRange: range %d..%d is out of bounds for page %d (0..%d characters).',
      [AStartIndex, AStartIndex + ACount - 1, FPageIndex, FTextPage.CharCount]));
  FSelection.SelectRange(AStartIndex, ACount);
  FShownStart := AStartIndex;
  FShownCount := ACount;
  FPaintBox.Invalidate;
  if Assigned(FOnTextSelected) then
    FOnTextSelected(Self);
  { Scroll so the top of the match is visible, the same PDF-space -> scrollbar
    pixel conversion GotoBookmark uses. }
  bounds := FTextPage.BoundsForRange(AStartIndex, ACount);
  page := FDocument.Pages[FPageIndex];
  pixelY := Round((page.Height - bounds.Top) * FZoom * DPIScale);
  if pixelY < 0 then
    pixelY := 0;
  VertScrollBar.Position := pixelY;
end;

procedure TPdfViewer.ClearSelection;
begin
  FShownStart := -1;
  FShownCount := 0;
  if FSelection <> nil then
    FSelection.Clear;
  if FPaintBox <> nil then
    FPaintBox.Invalidate;
end;

procedure Register;
begin
  RegisterComponents('PDFium', [TPdfViewer]);
end;

initialization
  {$I pdfium4laz.lrs}

end.
