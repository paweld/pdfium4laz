unit PdfiumThumbnails;

{$mode objfpc}{$H+}{$inline on}

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, ExtCtrls,
  PdfiumLib, PdfiumCore, PdfiumRender, PdfiumThumbnailCache;

type
  TPdfThumbOrientation = (toVertical, toHorizontal);
  TPdfThumbClickEvent = procedure(Sender: TObject; APageIndex: Integer) of object;
  TPdfCacheProgressEvent = procedure(Sender: TObject; ARendered, ATotal: Integer) of object;
  TPdfPageCaptionEvent = procedure(Sender: TObject; APageIndex: Integer; var ACaption: String) of object;

  TPdfThumbLineInfo = record
    FirstPage: Integer;
    Count: Integer;
    MainExtent: Integer;
  end;

  TPdfThumbnailPanel = class(TScrollBox)
  private
    FDocument: TPdfDocument;
    FCache: TPdfThumbnailCache;
    FThumbnailWidth: Integer;
    FMarginHorizontal: Integer;
    FMarginVertical: Integer;
    FOrientation: TPdfThumbOrientation;
    FSelectedIndex: Integer;
    FSelectedBorderColor: TColor;
    FBackgroundColor: TColor;
    FLabelVisible: Boolean;
    FLabelFont: TFont;
    FOnPageClick: TPdfThumbClickEvent;
    FOnCacheProgress: TPdfCacheProgressEvent;
    FOnCacheComplete: TNotifyEvent;
    FOnPageCaption: TPdfPageCaptionEvent;
    FPageAspect: array of Double;
    FRenderedCount: Integer;
    FPaintBox: TPaintBox;
    FPageLine: array of Integer;
    FPageCrossOffset: array of Integer;
    FLines: array of TPdfThumbLineInfo;
    FLineStart: array of Integer;
    FMainScale: Double;
    FCrossScale: Double;
    FColorScheme: TPdfColorScheme;

    procedure SetDocument(AValue: TPdfDocument);
    procedure SetThumbnailWidth(AValue: Integer);
    procedure SetMarginHorizontal(AValue: Integer);
    procedure SetMarginVertical(AValue: Integer);
    procedure SetOrientation(AValue: TPdfThumbOrientation);
    procedure SetSelectedIndex(AValue: Integer);
    procedure SetSelectedBorderColor(AValue: TColor);
    procedure SetBackgroundColor(AValue: TColor);
    procedure SetUseColorScheme(AValue: Boolean);
    procedure SetSchemePathFillColor(AValue: TColor);
    procedure SetSchemePathStrokeColor(AValue: TColor);
    procedure SetSchemeTextFillColor(AValue: TColor);
    procedure SetSchemeTextStrokeColor(AValue: TColor);
    procedure SetSchemeBackgroundColor(AValue: TColor);
    procedure SetInvertImageColors(AValue: Boolean);
    procedure SetLabelFont(AValue: TFont);
    procedure LabelFontChanged(Sender: TObject);
    function CellHeight(APageIndex: Integer): Integer;
    function LabelHeight: Integer;
    function ItemCrossExtent(APageIndex: Integer): Integer;
    function ItemMainExtent(APageIndex: Integer): Integer;
    function MainPadding: Integer;
    function CrossPadding: Integer;
    function CellRect(APageIndex: Integer): TRect;
    function ClampedRange(AExtent, AViewportExtent: Integer; out AScale: Double): Integer;
    function MainAxisScrollPos: Integer;
    procedure SetMainAxisScrollPos(AValue: Integer);
    function CrossAxisScrollPos: Integer;
    function FindLineAtOffset(AOffset: Integer): Integer;
    function GetVisibleRange(out AFirst, ALast: Integer): Boolean;
    procedure HandleThumbnailReady(Sender: TObject; APageIndex: Integer);
    function PageAtPoint(X, Y: Integer): Integer;
    procedure RebuildLayout;
    procedure PinPaintBoxBounds;
    procedure UpdateScrollPages;
    procedure PaintBoxPaint(Sender: TObject);
    procedure PaintBoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
  protected
    procedure DoOnResize; override;
    property Color;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure ScrollBy(DeltaX, DeltaY: Integer); override;
    procedure ScrollToPage(APageIndex: Integer);
    procedure InvalidateCache;
    procedure StopCacheThread;
  published
    property Document: TPdfDocument read FDocument write SetDocument;
    property ThumbnailWidth: Integer read FThumbnailWidth write SetThumbnailWidth default 120;
    property MarginHorizontal: Integer read FMarginHorizontal write SetMarginHorizontal default 8;
    property MarginVertical: Integer read FMarginVertical write SetMarginVertical default 8;
    property Orientation: TPdfThumbOrientation read FOrientation write SetOrientation default toVertical;
    property SelectedIndex: Integer read FSelectedIndex write SetSelectedIndex;
    property SelectedBorderColor: TColor read FSelectedBorderColor write SetSelectedBorderColor default clHighlight;
    property BackgroundColor: TColor read FBackgroundColor write SetBackgroundColor default $00B2B2B2;
    { Changing this (or any Scheme* color, or InvertImageColors) fully
      rebuilds the thumbnail cache - while False, the fast embedded-thumbnail
      path is used instead, since PDFium can't recolor an already-flattened
      bitmap after the fact. }
    property UseColorScheme: Boolean read FColorScheme.Enabled write SetUseColorScheme default False;
    property SchemePathFillColor: TColor read FColorScheme.PathFillColor write SetSchemePathFillColor default clSilver;
    property SchemePathStrokeColor: TColor read FColorScheme.PathStrokeColor write SetSchemePathStrokeColor default clSilver;
    property SchemeTextFillColor: TColor read FColorScheme.TextFillColor write SetSchemeTextFillColor default clWhite;
    property SchemeTextStrokeColor: TColor read FColorScheme.TextStrokeColor write SetSchemeTextStrokeColor default clWhite;
    property SchemeBackgroundColor: TColor read FColorScheme.BackgroundColor write SetSchemeBackgroundColor default $00202020;
    { EXPERIMENTAL, same known limitation as TPdfViewer.InvertImageColors.
      UNLIKE that property, this one only has any effect while UseColorScheme
      is also True - thumbnails have no "normal page, only images inverted" use case. }
    property InvertImageColors: Boolean read FColorScheme.InvertImages write SetInvertImageColors default False;
    property LabelVisible: Boolean read FLabelVisible write FLabelVisible default True;
    property LabelFont: TFont read FLabelFont write SetLabelFont;
    property OnPageCaption: TPdfPageCaptionEvent read FOnPageCaption write FOnPageCaption;
    property OnPageClick: TPdfThumbClickEvent read FOnPageClick write FOnPageClick;
    property OnCacheProgress: TPdfCacheProgressEvent read FOnCacheProgress write FOnCacheProgress;
    property OnCacheComplete: TNotifyEvent read FOnCacheComplete write FOnCacheComplete;
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
  TPaintBoxAccess = class(TPaintBox);

const
  CAPTION_HEIGHT = 18;
  { KNOWN QUIRK: Windows' native scrollbar hangs the calling thread above
    roughly Range=100000 (with a background render thread active). }
  MAX_NATIVE_SCROLL_RANGE = 32000;

constructor TPdfThumbnailPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  AutoScroll := False;
  FThumbnailWidth := 120;
  FMarginHorizontal := 8;
  FMarginVertical := 8;
  FOrientation := toVertical;
  FSelectedIndex := -1;
  FSelectedBorderColor := clHighlight;
  FBackgroundColor := $00B2B2B2;
  FLabelVisible := True;
  FLabelFont := TFont.Create;
  FLabelFont.Size := 8;
  FLabelFont.OnChange := @LabelFontChanged;
  Color := FBackgroundColor;
  FMainScale := 1.0;
  FCrossScale := 1.0;
  FColorScheme.Enabled := False;
  FColorScheme.PathFillColor := clSilver;
  FColorScheme.PathStrokeColor := clSilver;
  FColorScheme.TextFillColor := clWhite;
  FColorScheme.TextStrokeColor := clWhite;
  FColorScheme.BackgroundColor := $00202020;
  FColorScheme.InvertImages := False;
  { Anchors must stay [akLeft, akTop] (not [] or alClient), or AlignControls
    fights PinPaintBoxBounds's own positioning on every resize. }
  FPaintBox := TPaintBox.Create(Self);
  FPaintBox.Parent := Self;
  FPaintBox.Anchors := [akLeft, akTop];
  FPaintBox.OnPaint := @PaintBoxPaint;
  PinPaintBoxBounds;
  FPaintBox.OnMouseDown := @PaintBoxMouseDown;
end;

destructor TPdfThumbnailPanel.Destroy;
begin
  FreeAndNil(FCache);
  FLabelFont.Free;
  inherited Destroy;
end;

procedure TPdfThumbnailPanel.SetDocument(AValue: TPdfDocument);
var
  i, n: Integer;
  size: TPdfPageSize;
begin
  if FDocument = AValue then
    exit;
  FreeAndNil(FCache);
  FDocument := AValue;
  FSelectedIndex := -1;
  FRenderedCount := 0;
  SetLength(FPageAspect, 0);
  if FDocument <> nil then
  begin
    n := FDocument.PageCount;
    SetLength(FPageAspect, n);
    for i := 0 to n - 1 do
    begin
      size := FDocument.PageSizes[i];
      if size.Width > 0 then
        FPageAspect[i] := size.Height / size.Width
      else
        FPageAspect[i] := 1.4;
    end;
    FCache := TPdfThumbnailCache.CreateWithScheme(FDocument, FThumbnailWidth, FColorScheme, @HandleThumbnailReady);
  end;
  RebuildLayout;
end;

procedure TPdfThumbnailPanel.SetThumbnailWidth(AValue: Integer);
begin
  if AValue < 1 then
    AValue := 1;
  if FThumbnailWidth = AValue then
    exit;
  FThumbnailWidth := AValue;
  InvalidateCache;
end;

procedure TPdfThumbnailPanel.SetMarginHorizontal(AValue: Integer);
begin
  if AValue < 0 then
    AValue := 0;
  if FMarginHorizontal = AValue then
    exit;
  FMarginHorizontal := AValue;
  RebuildLayout;
end;

procedure TPdfThumbnailPanel.SetMarginVertical(AValue: Integer);
begin
  if AValue < 0 then
    AValue := 0;
  if FMarginVertical = AValue then
    exit;
  FMarginVertical := AValue;
  RebuildLayout;
end;

procedure TPdfThumbnailPanel.SetOrientation(AValue: TPdfThumbOrientation);
begin
  if FOrientation = AValue then
    exit;
  FOrientation := AValue;
  RebuildLayout;
end;

procedure TPdfThumbnailPanel.SetSelectedIndex(AValue: Integer);
begin
  if FSelectedIndex = AValue then
    exit;
  FSelectedIndex := AValue;
  FPaintBox.Invalidate;
end;

procedure TPdfThumbnailPanel.SetBackgroundColor(AValue: TColor);
begin
  if FBackgroundColor = AValue then
    exit;
  FBackgroundColor := AValue;
  FPaintBox.Invalidate;
end;

procedure TPdfThumbnailPanel.SetUseColorScheme(AValue: Boolean);
begin
  if FColorScheme.Enabled = AValue then
    exit;
  FColorScheme.Enabled := AValue;
  InvalidateCache;
end;

procedure TPdfThumbnailPanel.SetSchemePathFillColor(AValue: TColor);
begin
  if FColorScheme.PathFillColor = AValue then
    exit;
  FColorScheme.PathFillColor := AValue;
  if FColorScheme.Enabled then
    InvalidateCache;
end;

procedure TPdfThumbnailPanel.SetSchemePathStrokeColor(AValue: TColor);
begin
  if FColorScheme.PathStrokeColor = AValue then
    exit;
  FColorScheme.PathStrokeColor := AValue;
  if FColorScheme.Enabled then
    InvalidateCache;
end;

procedure TPdfThumbnailPanel.SetSchemeTextFillColor(AValue: TColor);
begin
  if FColorScheme.TextFillColor = AValue then
    exit;
  FColorScheme.TextFillColor := AValue;
  if FColorScheme.Enabled then
    InvalidateCache;
end;

procedure TPdfThumbnailPanel.SetSchemeTextStrokeColor(AValue: TColor);
begin
  if FColorScheme.TextStrokeColor = AValue then
    exit;
  FColorScheme.TextStrokeColor := AValue;
  if FColorScheme.Enabled then
    InvalidateCache;
end;

procedure TPdfThumbnailPanel.SetSchemeBackgroundColor(AValue: TColor);
begin
  if FColorScheme.BackgroundColor = AValue then
    exit;
  FColorScheme.BackgroundColor := AValue;
  if FColorScheme.Enabled then
    InvalidateCache;
end;

procedure TPdfThumbnailPanel.SetInvertImageColors(AValue: Boolean);
begin
  if FColorScheme.InvertImages = AValue then
    exit;
  FColorScheme.InvertImages := AValue;
  if FColorScheme.Enabled then
    InvalidateCache;
end;

procedure TPdfThumbnailPanel.SetSelectedBorderColor(AValue: TColor);
begin
  if FSelectedBorderColor = AValue then
    exit;
  FSelectedBorderColor := AValue;
  FPaintBox.Invalidate;
end;

procedure TPdfThumbnailPanel.SetLabelFont(AValue: TFont);
begin
  FLabelFont.Assign(AValue);
end;

procedure TPdfThumbnailPanel.LabelFontChanged(Sender: TObject);
begin
  FPaintBox.Invalidate;
end;

function TPdfThumbnailPanel.LabelHeight: Integer;
begin
  if FLabelVisible then
    Result := CAPTION_HEIGHT
  else
    Result := 0;
end;

function TPdfThumbnailPanel.CellHeight(APageIndex: Integer): Integer;
begin
  Result := Round(FThumbnailWidth * FPageAspect[APageIndex]);
  if Result < 1 then
    Result := 1;
end;

function TPdfThumbnailPanel.ItemCrossExtent(APageIndex: Integer): Integer;
begin
  if FOrientation = toVertical then
    Result := FThumbnailWidth
  else
    Result := CellHeight(APageIndex) + LabelHeight;
end;

function TPdfThumbnailPanel.ItemMainExtent(APageIndex: Integer): Integer;
begin
  if FOrientation = toVertical then
    Result := CellHeight(APageIndex) + LabelHeight
  else
    Result := FThumbnailWidth;
end;

function TPdfThumbnailPanel.MainPadding: Integer;
begin
  if FOrientation = toVertical then
    Result := FMarginVertical
  else
    Result := FMarginHorizontal;
end;

function TPdfThumbnailPanel.CrossPadding: Integer;
begin
  if FOrientation = toVertical then
    Result := FMarginHorizontal
  else
    Result := FMarginVertical;
end;

function TPdfThumbnailPanel.CellRect(APageIndex: Integer): TRect;
var
  mainPos, crossPos, h: Integer;
begin
  mainPos := FLineStart[FPageLine[APageIndex]];
  crossPos := FPageCrossOffset[APageIndex];
  h := CellHeight(APageIndex);
  if FOrientation = toVertical then
    Result := Rect(crossPos, mainPos, crossPos + FThumbnailWidth, mainPos + h)
  else
    Result := Rect(mainPos, crossPos, mainPos + FThumbnailWidth, crossPos + h);
end;

function TPdfThumbnailPanel.FindLineAtOffset(AOffset: Integer): Integer;
var
  lo, hi, mid: Integer;
begin
  Result := -1;
  if Length(FLines) = 0 then
    exit;
  if AOffset <= FLineStart[0] then
    exit(0);
  lo := 0;
  hi := High(FLines);
  while lo < hi do
  begin
    mid := (lo + hi + 1) div 2;
    if FLineStart[mid] <= AOffset then
      lo := mid
    else
      hi := mid - 1;
  end;
  Result := lo;
end;

function TPdfThumbnailPanel.ClampedRange(AExtent, AViewportExtent: Integer; out AScale: Double): Integer;
begin
  if AExtent <= MAX_NATIVE_SCROLL_RANGE then
  begin
    Result := AExtent;
    AScale := 1.0;
  end
  else
  begin
    Result := MAX_NATIVE_SCROLL_RANGE;
    { Win32 clamps Position to (Range - raw ClientWidth/Height), not
      (Range - Page) as documented. }
    if AViewportExtent < Result then
      AScale := (AExtent - AViewportExtent) / (Result - AViewportExtent)
    else
      AScale := AExtent / Result;
  end;
end;

function TPdfThumbnailPanel.MainAxisScrollPos: Integer;
begin
  if FOrientation = toVertical then
    Result := Round(VertScrollBar.Position * FMainScale)
  else
    Result := Round(HorzScrollBar.Position * FMainScale);
end;

procedure TPdfThumbnailPanel.SetMainAxisScrollPos(AValue: Integer);
begin
  if FOrientation = toVertical then
    VertScrollBar.Position := Round(AValue / FMainScale)
  else
    HorzScrollBar.Position := Round(AValue / FMainScale);
end;

function TPdfThumbnailPanel.CrossAxisScrollPos: Integer;
begin
  if FOrientation = toVertical then
    Result := Round(HorzScrollBar.Position * FCrossScale)
  else
    Result := Round(VertScrollBar.Position * FCrossScale);
end;

function TPdfThumbnailPanel.GetVisibleRange(out AFirst, ALast: Integer): Boolean;
var
  scrollPos, viewportExtent, firstLine, lastLine: Integer;
begin
  AFirst := 0;
  ALast := -1;
  if (FDocument = nil) or (FDocument.PageCount = 0) or (Length(FLines) = 0) then
    exit(False);
  scrollPos := MainAxisScrollPos;
  { Self.ClientWidth/Height, not FPaintBox's - once the scrollbar Range
    exceeds the visible area, the widgetset reports FPaintBox's own size as
    the full logical scroll extent, not the true visible viewport. }
  if FOrientation = toVertical then
    viewportExtent := ClientHeight
  else
    viewportExtent := ClientWidth;
  firstLine := FindLineAtOffset(scrollPos);
  lastLine := FindLineAtOffset(scrollPos + viewportExtent);
  if lastLine < firstLine then
    lastLine := firstLine;
  if lastLine > High(FLines) then
    lastLine := High(FLines);
  AFirst := FLines[firstLine].FirstPage;
  ALast := FLines[lastLine].FirstPage + FLines[lastLine].Count - 1;
  Result := True;
end;

procedure TPdfThumbnailPanel.RebuildLayout;
var
  i, n, pageCount, crossAvail, crossUsed, itemCross, itemMain: Integer;
  mainPad, crossPad, lineFirst, lineMaxMain, crossExtentTotal, mainViewport: Integer;
begin
  if FPaintBox = nil then
    exit;
  { DoSetBounds, not SetBounds: the latter's post-resize notification chain
    can re-enter this procedure mid-layout-rebuild on Win32. }
  TPaintBoxAccess(FPaintBox).DoSetBounds(0, 0, ClientWidth, ClientHeight);
  SetLength(FPageLine, 0);
  SetLength(FPageCrossOffset, 0);
  SetLength(FLines, 0);
  SetLength(FLineStart, 0);
  pageCount := 0;
  if FDocument <> nil then
    pageCount := FDocument.PageCount;
  if pageCount = 0 then
  begin
    FMainScale := 1.0;
    FCrossScale := 1.0;
    VertScrollBar.Range := 0;
    HorzScrollBar.Range := 0;
    UpdateScrollPages;
    FPaintBox.Invalidate;
    exit;
  end;
  SetLength(FPageLine, pageCount);
  SetLength(FPageCrossOffset, pageCount);
  mainPad := MainPadding;
  crossPad := CrossPadding;
  { Self.ClientWidth/Height, not FPaintBox's - see GetVisibleRange. }
  if FOrientation = toVertical then
  begin
    crossAvail := ClientWidth;
    mainViewport := ClientHeight;
  end
  else
  begin
    crossAvail := ClientHeight;
    mainViewport := ClientWidth;
  end;
  if crossAvail < 1 then
    crossAvail := 1;
  crossExtentTotal := 0;
  n := 0;
  i := 0;
  while i < pageCount do
  begin
    lineFirst := i;
    crossUsed := crossPad;
    lineMaxMain := 0;
    while i < pageCount do
    begin
      itemCross := ItemCrossExtent(i) + crossPad;
      if (i > lineFirst) and (crossUsed + itemCross > crossAvail) then
        break;
      FPageCrossOffset[i] := crossUsed;
      crossUsed := crossUsed + itemCross;
      itemMain := ItemMainExtent(i);
      if itemMain > lineMaxMain then
        lineMaxMain := itemMain;
      FPageLine[i] := n;
      Inc(i);
    end;
    SetLength(FLines, n + 1);
    FLines[n].FirstPage := lineFirst;
    FLines[n].Count := i - lineFirst;
    FLines[n].MainExtent := lineMaxMain + mainPad;
    if crossUsed > crossExtentTotal then
      crossExtentTotal := crossUsed;
    Inc(n);
  end;
  SetLength(FLineStart, n + 1);
  FLineStart[0] := mainPad;
  for i := 0 to n - 1 do
    FLineStart[i + 1] := FLineStart[i] + FLines[i].MainExtent;
  if FOrientation = toVertical then
  begin
    VertScrollBar.Range := ClampedRange(FLineStart[n], mainViewport, FMainScale);
    HorzScrollBar.Range := ClampedRange(crossExtentTotal, crossAvail, FCrossScale);
  end
  else
  begin
    HorzScrollBar.Range := ClampedRange(FLineStart[n], mainViewport, FMainScale);
    VertScrollBar.Range := ClampedRange(crossExtentTotal, crossAvail, FCrossScale);
  end;
  UpdateScrollPages;
  PinPaintBoxBounds;
end;

{ Positions FPaintBox AT the current scroll offset, not a fixed (0,0) -
  pinning it to a literal (0,0) instead made the panel go blank once
  scrolled. DoSetBounds, not SetBounds, for the same reentrancy reason as
  RebuildLayout. }
procedure TPdfThumbnailPanel.PinPaintBoxBounds;
begin
  if FPaintBox = nil then
    exit;
  TPaintBoxAccess(FPaintBox).DoSetBounds(HorzScrollBar.Position, VertScrollBar.Position, ClientWidth, ClientHeight);
  FPaintBox.Invalidate;
end;

procedure TPdfThumbnailPanel.UpdateScrollPages;
var
  vertScale, horzScale: Double;
begin
  if FPaintBox = nil then
    exit;
  if FOrientation = toVertical then
  begin
    vertScale := FMainScale;
    horzScale := FCrossScale;
  end
  else
  begin
    vertScale := FCrossScale;
    horzScale := FMainScale;
  end;
  { Self.ClientWidth/Height, not FPaintBox's - see GetVisibleRange. }
  VertScrollBar.Page := Round(ClientHeight / vertScale);
  HorzScrollBar.Page := Round(ClientWidth / horzScale);
end;

procedure TPdfThumbnailPanel.DoOnResize;
begin
  inherited DoOnResize;
  RebuildLayout;
end;

function TPdfThumbnailPanel.PageAtPoint(X, Y: Integer): Integer;
var
  line, p: Integer;
  contentX, contentY, mainCoord: Integer;
  r: TRect;
begin
  Result := -1;
  if (FDocument = nil) or (Length(FLines) = 0) then
    exit;
  if FOrientation = toVertical then
  begin
    contentX := X + CrossAxisScrollPos;
    contentY := Y + MainAxisScrollPos;
    mainCoord := contentY;
  end
  else
  begin
    contentX := X + MainAxisScrollPos;
    contentY := Y + CrossAxisScrollPos;
    mainCoord := contentX;
  end;
  line := FindLineAtOffset(mainCoord);
  if (line < 0) or (line > High(FLines)) then
    exit;
  for p := FLines[line].FirstPage to FLines[line].FirstPage + FLines[line].Count - 1 do
  begin
    r := CellRect(p);
    Inc(r.Bottom, LabelHeight);
    if PtInRect(r, Point(contentX, contentY)) then
      exit(p);
  end;
end;

procedure TPdfThumbnailPanel.PaintBoxPaint(Sender: TObject);
var
  i, first, last, scrollX, scrollY: Integer;
  r, border: TRect;
  bmp: TBitmap;
  captionRect: TRect;
  pageCaption: String;
begin
  { ClientWidth/Height, not FPaintBox's - see the comment in GetVisibleRange. }
  FPaintBox.Canvas.Brush.Color := FBackgroundColor;
  FPaintBox.Canvas.FillRect(Rect(0, 0, ClientWidth, ClientHeight));
  if (FDocument = nil) or (not GetVisibleRange(first, last)) then
    exit;
  if FOrientation = toVertical then
  begin
    scrollY := MainAxisScrollPos;
    scrollX := CrossAxisScrollPos;
  end
  else
  begin
    scrollX := MainAxisScrollPos;
    scrollY := CrossAxisScrollPos;
  end;
  for i := first to last do
  begin
    r := CellRect(i);
    OffsetRect(r, -scrollX, -scrollY);
    if FCache <> nil then
      bmp := FCache.GetBitmap(i)
    else
      bmp := nil;
    if bmp <> nil then
      FPaintBox.Canvas.Draw(r.Left, r.Top, bmp)
    else
    begin
      FPaintBox.Canvas.Brush.Color := clSilver;
      FPaintBox.Canvas.FillRect(r);
    end;
    FPaintBox.Canvas.Pen.Color := clGray;
    FPaintBox.Canvas.Brush.Style := bsClear;
    FPaintBox.Canvas.Rectangle(r);
    FPaintBox.Canvas.Brush.Style := bsSolid;
    if i = FSelectedIndex then
    begin
      border := r;
      InflateRect(border, 2, 2);
      FPaintBox.Canvas.Pen.Color := FSelectedBorderColor;
      FPaintBox.Canvas.Brush.Style := bsClear;
      FPaintBox.Canvas.Rectangle(border);
      FPaintBox.Canvas.Brush.Style := bsSolid;
    end;
    if FLabelVisible then
    begin
      captionRect := Rect(r.Left, r.Bottom, r.Right, r.Bottom + CAPTION_HEIGHT);
      pageCaption := Format('Page %d', [i + 1]);
      if Assigned(FOnPageCaption) then
        FOnPageCaption(Self, i, pageCaption);
      FPaintBox.Canvas.Font := FLabelFont;
      FPaintBox.Canvas.Brush.Style := bsClear;
      FPaintBox.Canvas.TextRect(captionRect, captionRect.Left, captionRect.Top, pageCaption);
      FPaintBox.Canvas.Brush.Style := bsSolid;
    end;
  end;
end;

procedure TPdfThumbnailPanel.PaintBoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  idx: Integer;
begin
  SetFocus;
  if Button <> mbLeft then
    exit;
  idx := PageAtPoint(X, Y);
  if idx < 0 then
    exit;
  SelectedIndex := idx;
  if Assigned(FOnPageClick) then
    FOnPageClick(Self, idx);
end;

{ Uses Sender (the posting cache), not FCache - a cache being torn down can
  still drain queued notifications after FCache has already been nilled. }
procedure TPdfThumbnailPanel.HandleThumbnailReady(Sender: TObject; APageIndex: Integer);
var
  cache: TPdfThumbnailCache;
begin
  cache := TPdfThumbnailCache(Sender);
  Inc(FRenderedCount);
  FPaintBox.Invalidate;
  if Assigned(FOnCacheProgress) then
    FOnCacheProgress(Self, FRenderedCount, cache.PageCount);
  if (FRenderedCount >= cache.PageCount) and Assigned(FOnCacheComplete) then
    FOnCacheComplete(Self);
end;

procedure TPdfThumbnailPanel.ScrollBy(DeltaX, DeltaY: Integer);
begin
  PinPaintBoxBounds;
end;

procedure TPdfThumbnailPanel.ScrollToPage(APageIndex: Integer);
var
  lineStart, lineExtent, viewportExtent, target, maxScroll: Integer;
begin
  if (FDocument = nil) or (APageIndex < 0) or (APageIndex >= FDocument.PageCount) or (Length(FLines) = 0) then
    exit;
  lineStart := FLineStart[FPageLine[APageIndex]];
  lineExtent := FLines[FPageLine[APageIndex]].MainExtent;
  if FOrientation = toVertical then
    viewportExtent := ClientHeight
  else
    viewportExtent := ClientWidth;
  target := lineStart - (viewportExtent - lineExtent) div 2;
  maxScroll := FLineStart[High(FLineStart)] - viewportExtent;
  if maxScroll < 0 then
    maxScroll := 0;
  if target < 0 then
    target := 0;
  if target > maxScroll then
    target := maxScroll;
  SetMainAxisScrollPos(target);
  FPaintBox.Invalidate;
end;

procedure TPdfThumbnailPanel.InvalidateCache;
var
  doc: TPdfDocument;
begin
  doc := FDocument;
  FDocument := nil;
  SetDocument(doc);
end;

procedure TPdfThumbnailPanel.StopCacheThread;
begin
  FreeAndNil(FCache);
end;

procedure Register;
begin
  RegisterComponents('PDFium', [TPdfThumbnailPanel]);
end;

end.
