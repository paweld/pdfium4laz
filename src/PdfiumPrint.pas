unit PdfiumPrint;

{$mode objfpc}{$H+}{$inline on}

interface

uses
  Classes, SysUtils, Types, SyncObjs, Graphics, Printers, PdfiumLib, PdfiumCore, PdfiumRender;

type
  { How a page's PDF-point size maps onto the physical printed page. }
  TPdfPrintPageSize = (
    ppsOriginal,      // print at the page's real size (1:1 via the printer's DPI); may exceed the paper and get clipped by the driver
    ppsFitToPage,     // always scale to fill the printer's printable area, up or down, preserving aspect ratio
    ppsShrinkToFit    // like ppsFitToPage, but only ever scales down - a page smaller than the paper prints at its real size
  );

  { Which PDFium call actually draws each page. }
  TPdfPrintEngine = (
    ppeAuto,             // FPDF_RenderPage (direct-to-HDC) on Windows, FPDF_RenderPageBitmap everywhere else
    ppeRenderPage,       // force FPDF_RenderPage - Windows only, raises EPdfiumError elsewhere
    ppeRenderPageBitmap  // force FPDF_RenderPageBitmap - works on every platform
  );

  { An inclusive, 0-based page range. FirstPage must be <= LastPage. }
  TPdfPageRange = record
    FirstPage: Integer;
    LastPage: Integer;
  end;

  TPdfPrintOptions = record
    PrinterName: String;         // required - EPdfiumError if empty or not an installed printer name
    Copies: Integer;
    PageSize: TPdfPrintPageSize;
    CenterOnPage: Boolean;
    Engine: TPdfPrintEngine;
  end;

function PdfDefaultPrintOptions: TPdfPrintOptions;
function PdfPageRange(AFirstPage, ALastPage: Integer): TPdfPageRange;

{ 1-based (matching a print dialog, not this library's usual 0-based
  convention): '*' every page, '5' page 5, '1,3,5,8', '1-3,5,15'. Returns
  sorted, deduplicated 0-based indices. }
function PdfParsePageSpec(const ASpec: String; APageCount: Integer): TIntegerDynArray;

procedure PdfPrintPages(ADocument: TPdfDocument; const ARanges: array of TPdfPageRange;
  const APages: array of Integer; const AOptions: TPdfPrintOptions); overload;
procedure PdfPrintPages(ADocument: TPdfDocument; const APageSpec: String;
  const AOptions: TPdfPrintOptions); overload;
procedure PdfPrintDocument(ADocument: TPdfDocument; const AOptions: TPdfPrintOptions);

type
  TPdfPrintJob = class(TThread)
  private
    FDocHandle: FPDF_DOCUMENT;
    FPdfLock: TCriticalSection;
    FPages: TIntegerDynArray;
    FOptions: TPdfPrintOptions;
    FEngine: TPdfPrintEngine;
    FXDPI, FYDPI, FPrinterPageWidth, FPrinterPageHeight: Integer;
    FOnAfterPagePrint: TNotifyEvent;
    FOnAfterDocumentPrint: TNotifyEvent;
    FCancelled: Boolean;
    FErrorMessage: String;
    FPrintedCount: Integer;
    FPageIndex: Integer;
    FCurrentBitmap: FPDF_BITMAP;
    FDestX, FDestY, FDestWidth, FDestHeight: Integer;
    procedure DoBeginDoc;
    procedure DoPrintCurrentPage;
    procedure DoFinish;
    function GetPageCount: Integer;
    function GetSucceeded: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(ADocument: TPdfDocument; const APages: array of Integer; const AOptions: TPdfPrintOptions;
      AAfterPagePrint, AAfterDocumentPrint: TNotifyEvent);
    procedure Cancel;
    property PageIndex: Integer read FPageIndex;
    property PrintedCount: Integer read FPrintedCount;
    property PageCount: Integer read GetPageCount;
    property Cancelled: Boolean read FCancelled;
    property ErrorMessage: String read FErrorMessage;
    property Succeeded: Boolean read GetSucceeded;
  end;

function PdfPrintPagesAsync(ADocument: TPdfDocument; const ARanges: array of TPdfPageRange;   const APages: array of Integer; const AOptions: TPdfPrintOptions;
  AAfterPagePrint: TNotifyEvent = nil; AAfterDocumentPrint: TNotifyEvent = nil): TPdfPrintJob; overload;
function PdfPrintPagesAsync(ADocument: TPdfDocument; const APageSpec: String; const AOptions: TPdfPrintOptions;
  AAfterPagePrint: TNotifyEvent = nil; AAfterDocumentPrint: TNotifyEvent = nil): TPdfPrintJob; overload;
function PdfPrintDocumentAsync(ADocument: TPdfDocument; const AOptions: TPdfPrintOptions;
  AAfterPagePrint: TNotifyEvent = nil; AAfterDocumentPrint: TNotifyEvent = nil): TPdfPrintJob;
function PdfPrintJobActive: Boolean;

type
  TPdfDocumentPrintHelper = class helper for TPdfDocument
    procedure Print(const APrinterName, APageSpec: String; ACopies: Integer = 1); overload;
    procedure Print(const APageSpec: String; const AOptions: TPdfPrintOptions); overload;
    function PrintAsync(const APageSpec: String; const AOptions: TPdfPrintOptions;
      AAfterPagePrint: TNotifyEvent = nil; AAfterDocumentPrint: TNotifyEvent = nil): TPdfPrintJob;
  end;

implementation

function PdfDefaultPrintOptions: TPdfPrintOptions;
begin
  Result.PrinterName := '';
  Result.Copies := 1;
  Result.PageSize := ppsShrinkToFit;
  Result.CenterOnPage := True;
  Result.Engine := ppeAuto;
end;

function PdfPageRange(AFirstPage, ALastPage: Integer): TPdfPageRange;
begin
  Result.FirstPage := AFirstPage;
  Result.LastPage := ALastPage;
end;

function PdfParsePageSpec(const ASpec: String; APageCount: Integer): TIntegerDynArray;
var
  trimmedSpec, token, leftPart, rightPart: String;
  tokens: TStringList;
  seen: array of Boolean;
  i, dashPos, firstPage, lastPage, pageNum, count: Integer;

  procedure MarkPage(AUserFacingPageNum: Integer);
  begin
    if (AUserFacingPageNum < 1) or (AUserFacingPageNum > APageCount) then
      raise EPdfiumError.CreateFmt('PdfParsePageSpec: page %d is out of range for a %d-page document.', [AUserFacingPageNum, APageCount]);
    seen[AUserFacingPageNum - 1] := True;
  end;

begin
  trimmedSpec := Trim(ASpec);
  if trimmedSpec = '' then
    raise EPdfiumError.Create('PdfParsePageSpec: ASpec must not be empty.');
  SetLength(seen, APageCount);
  if trimmedSpec = '*' then
  begin
    for i := 0 to APageCount - 1 do
      seen[i] := True;
  end
  else
  begin
    tokens := TStringList.Create;
    try
      tokens.StrictDelimiter := True;
      tokens.Delimiter := ',';
      tokens.DelimitedText := trimmedSpec;
      for i := 0 to tokens.Count - 1 do
      begin
        token := Trim(tokens[i]);
        if token = '' then
          raise EPdfiumError.CreateFmt('PdfParsePageSpec: empty entry in "%s".', [ASpec]);
        dashPos := Pos('-', token);
        if dashPos > 0 then
        begin
          leftPart := Trim(Copy(token, 1, dashPos - 1));
          rightPart := Trim(Copy(token, dashPos + 1, MaxInt));
          if (not TryStrToInt(leftPart, firstPage)) or (not TryStrToInt(rightPart, lastPage)) then
            raise EPdfiumError.CreateFmt('PdfParsePageSpec: "%s" is not a valid page range.', [token]);
          if firstPage > lastPage then
            raise EPdfiumError.CreateFmt('PdfParsePageSpec: "%s" is a reversed range (first page must not be greater than last page).', [token]);
          for pageNum := firstPage to lastPage do
            MarkPage(pageNum);
        end
        else
        begin
          if not TryStrToInt(token, pageNum) then
            raise EPdfiumError.CreateFmt('PdfParsePageSpec: "%s" is not a valid page number.', [token]);
          MarkPage(pageNum);
        end;
      end;
    finally
      tokens.Free;
    end;
  end;

  count := 0;
  for i := 0 to APageCount - 1 do
  begin
    if seen[i] then
      Inc(count);
  end;
  SetLength(Result, count);
  count := 0;
  for i := 0 to APageCount - 1 do
  begin
    if seen[i] then
    begin
      Result[count] := i;
      Inc(count);
    end;
  end;
end;

procedure ComputePrintRect(APageWidthPt, APageHeightPt: Double; APageSize: TPdfPrintPageSize;
  ACenterOnPage: Boolean; AXDPI, AYDPI, APrinterPageWidth, APrinterPageHeight: Integer;
  out ADestX, ADestY, ADestWidth, ADestHeight: Integer);
var
  nativeWidth, nativeHeight: Double;
  scale, scaleX, scaleY: Double;
begin
  nativeWidth := APageWidthPt * AXDPI / 72;
  nativeHeight := APageHeightPt * AYDPI / 72;
  case APageSize of
    ppsFitToPage, ppsShrinkToFit:
      begin
        scaleX := APrinterPageWidth / nativeWidth;
        scaleY := APrinterPageHeight / nativeHeight;
        if scaleX < scaleY then
          scale := scaleX
        else
          scale := scaleY;
        if (APageSize = ppsShrinkToFit) and (scale > 1.0) then
          scale := 1.0;
        nativeWidth := nativeWidth * scale;
        nativeHeight := nativeHeight * scale;
      end;
  end;
  ADestWidth := Round(nativeWidth);
  ADestHeight := Round(nativeHeight);
  if ADestWidth < 1 then
    ADestWidth := 1;
  if ADestHeight < 1 then
    ADestHeight := 1;
  if ACenterOnPage then
  begin
    ADestX := (APrinterPageWidth - ADestWidth) div 2;
    ADestY := (APrinterPageHeight - ADestHeight) div 2;
  end
  else
  begin
    ADestX := 0;
    ADestY := 0;
  end;
end;

procedure SelectPrinterOrRaise(const APrinterName: String);
var
  idx: Integer;
begin
  if Printer = nil then
    raise EPdfiumError.Create('PdfiumPrint: no printing backend is available (Printer is nil). The application project must add ' +
      'the standard Printer4Lazarus package for TPrinter to be functional - PdfiumPrint.pas itself needs ' +
      'no such package, only LCL''s own Printers unit, but an actual backend must still be linked in by ' +
      'the application, the same as any LCL app needs a widgetset.');
  if Trim(APrinterName) = '' then
    raise EPdfiumError.Create('PdfiumPrint: TPdfPrintOptions.PrinterName must be set to an installed printer''s name.');
  idx := Printer.Printers.IndexOf(APrinterName);
  if idx < 0 then
    raise EPdfiumError.CreateFmt('PdfiumPrint: no printer named "%s" is installed. Installed printers: %s.', [APrinterName, Printer.Printers.CommaText]);
  Printer.PrinterIndex := idx;
end;

function ResolveEngine(ARequested: TPdfPrintEngine): TPdfPrintEngine;
begin
  Result := ARequested;
  if Result = ppeAuto then
  begin
    if PdfiumRenderPageAvailable then
      Result := ppeRenderPage
    else
      Result := ppeRenderPageBitmap;
  end
  else if (Result = ppeRenderPage) and (not PdfiumRenderPageAvailable) then
    raise EPdfiumError.Create('PdfiumPrint: TPdfPrintOptions.Engine was set to ppeRenderPage, but FPDF_RenderPage is only available on Windows.');
end;

{ Must run on the main thread - Printer.Canvas belongs to it. }
{$IFDEF WINDOWS}
procedure PrintPageViaRenderPage(APage: TPdfPage; ADestX, ADestY, ADestWidth, ADestHeight: Integer);
begin
  APage.Document.Lock.Enter;
  try
    FPDF_RenderPage(Printer.Canvas.Handle, APage.Handle, ADestX, ADestY, ADestWidth, ADestHeight, 0, FPDF_ANNOT);
  finally
    APage.Document.Lock.Leave;
  end;
end;
{$ENDIF}

{ Runs on the main thread, so holding the lock across the TBitmap conversion
  is safe here - unlike PdfiumThumbnailCache.pas's background thread. }
procedure PrintPageViaBitmap(APage: TPdfPage; ADestX, ADestY, ADestWidth, ADestHeight: Integer);
var
  fpdfBitmap: FPDF_BITMAP;
  bmp: TBitmap;
begin
  APage.Document.Lock.Enter;
  try
    fpdfBitmap := FPDFBitmap_CreateEx(ADestWidth, ADestHeight, FPDFBitmap_BGRA, nil, 0);
    if fpdfBitmap = nil then
      raise EPdfiumError.Create('PdfiumPrint: could not allocate a print bitmap.');
    try
      FPDFBitmap_FillRect(fpdfBitmap, 0, 0, ADestWidth, ADestHeight, $FFFFFFFF);
      FPDF_RenderPageBitmap(fpdfBitmap, APage.Handle, 0, 0, ADestWidth, ADestHeight, 0, FPDF_ANNOT);
      bmp := PdfiumBitmapToTBitmap(fpdfBitmap);
    finally
      FPDFBitmap_Destroy(fpdfBitmap);
    end;
  finally
    APage.Document.Lock.Leave;
  end;
  try
    Printer.Canvas.Draw(ADestX, ADestY, bmp);
  finally
    bmp.Free;
  end;
end;

procedure PrintOnePage(ADocument: TPdfDocument; APageIndex: Integer; AEngine: TPdfPrintEngine;
  APageSize: TPdfPrintPageSize; ACenterOnPage: Boolean);
var
  page: TPdfPage;
  destX, destY, destWidth, destHeight: Integer;
begin
  page := ADocument.Pages[APageIndex];
  ComputePrintRect(page.Width, page.Height, APageSize, ACenterOnPage,
    Printer.XDPI, Printer.YDPI, Printer.PageWidth, Printer.PageHeight, destX, destY, destWidth, destHeight);
  {$IFDEF WINDOWS}
  if AEngine = ppeRenderPage then
    PrintPageViaRenderPage(page, destX, destY, destWidth, destHeight)
  else
  {$ENDIF}
    PrintPageViaBitmap(page, destX, destY, destWidth, destHeight);
end;

{ Validates ARanges/APages and merges them into sorted, deduplicated 0-based indices. }
function CollectPrintPages(const ACaller: String; ADocument: TPdfDocument; const ARanges: array of TPdfPageRange;
  const APages: array of Integer): TIntegerDynArray;
var
  pageCount, i, j, count: Integer;
  seen: array of Boolean;
begin
  if ADocument = nil then
    raise EPdfiumError.CreateFmt('%s: ADocument must not be nil.', [ACaller]);
  pageCount := ADocument.PageCount;
  SetLength(seen, pageCount);
  for i := 0 to High(ARanges) do
  begin
    if (ARanges[i].FirstPage < 0) or (ARanges[i].LastPage >= pageCount) or
       (ARanges[i].FirstPage > ARanges[i].LastPage) then
      raise EPdfiumError.CreateFmt(
        '%s: invalid page range %d..%d for a %d-page document.',
        [ACaller, ARanges[i].FirstPage, ARanges[i].LastPage, pageCount]);
    for j := ARanges[i].FirstPage to ARanges[i].LastPage do
      seen[j] := True;
  end;
  for i := 0 to High(APages) do
  begin
    if (APages[i] < 0) or (APages[i] >= pageCount) then
      raise EPdfiumError.CreateFmt(
        '%s: page index %d is out of range for a %d-page document.', [ACaller, APages[i], pageCount]);
    seen[APages[i]] := True;
  end;
  count := 0;
  for i := 0 to pageCount - 1 do
  begin
    if seen[i] then
      Inc(count);
  end;
  if count = 0 then
    raise EPdfiumError.CreateFmt('%s: ARanges and APages must not both be empty.', [ACaller]);
  SetLength(Result, count);
  count := 0;
  for i := 0 to pageCount - 1 do
  begin
    if seen[i] then
    begin
      Result[count] := i;
      Inc(count);
    end;
  end;
end;

var
  GPrintJobActive: Boolean = False; // main thread only

function PdfPrintJobActive: Boolean;
begin
  Result := GPrintJobActive;
end;

procedure RaiseIfPrintJobActive(const ACaller: String);
begin
  if GPrintJobActive then
    raise EPdfiumError.CreateFmt('%s: a background print job (TPdfPrintJob) is still running - the global Printer is in use.', [ACaller]);
end;

procedure PdfPrintPages(ADocument: TPdfDocument; const ARanges: array of TPdfPageRange;
  const APages: array of Integer; const AOptions: TPdfPrintOptions);
var
  i: Integer;
  finalPages: TIntegerDynArray;
  engine: TPdfPrintEngine;
begin
  finalPages := CollectPrintPages('PdfPrintPages', ADocument, ARanges, APages);
  RaiseIfPrintJobActive('PdfPrintPages');
  SelectPrinterOrRaise(AOptions.PrinterName);
  engine := ResolveEngine(AOptions.Engine);
  Printer.Copies := AOptions.Copies;
  Printer.BeginDoc;
  try
    for i := 0 to High(finalPages) do
    begin
      if i > 0 then
        Printer.NewPage;
      PrintOnePage(ADocument, finalPages[i], engine, AOptions.PageSize, AOptions.CenterOnPage);
    end;
  finally
    Printer.EndDoc;
  end;
end;

procedure PdfPrintPages(ADocument: TPdfDocument; const APageSpec: String; const AOptions: TPdfPrintOptions);
var
  pages: TIntegerDynArray;
begin
  if ADocument = nil then
    raise EPdfiumError.Create('PdfPrintPages: ADocument must not be nil.');
  pages := PdfParsePageSpec(APageSpec, ADocument.PageCount);
  PdfPrintPages(ADocument, [], pages, AOptions);
end;

procedure PdfPrintDocument(ADocument: TPdfDocument; const AOptions: TPdfPrintOptions);
begin
  if ADocument = nil then
    raise EPdfiumError.Create('PdfPrintDocument: ADocument must not be nil.');
  PdfPrintPages(ADocument, [PdfPageRange(0, ADocument.PageCount - 1)], [], AOptions);
end;

{ TPdfPrintJob }

constructor TPdfPrintJob.Create(ADocument: TPdfDocument; const APages: array of Integer;
  const AOptions: TPdfPrintOptions; AAfterPagePrint, AAfterDocumentPrint: TNotifyEvent);
var
  i: Integer;
begin
  inherited Create(True);
  Priority := tpLower; // must not starve TPdfRenderWorker (PdfiumViewer.pas) for the document's Lock
  FDocHandle := ADocument.Handle;
  FPdfLock := ADocument.Lock;
  SetLength(FPages, Length(APages));
  for i := 0 to High(APages) do
    FPages[i] := APages[i];
  FOptions := AOptions;
  FEngine := ppeRenderPageBitmap;
  FOnAfterPagePrint := AAfterPagePrint;
  FOnAfterDocumentPrint := AAfterDocumentPrint;
  FPageIndex := -1;
end;

procedure TPdfPrintJob.Cancel;
begin
  FCancelled := True;
end;

function TPdfPrintJob.GetPageCount: Integer;
begin
  Result := Length(FPages);
end;

function TPdfPrintJob.GetSucceeded: Boolean;
begin
  Result := (FErrorMessage = '') and (not FCancelled) and (FPrintedCount = Length(FPages));
end;

{ Main thread. Captures the printer metrics once, so Execute never reads Printer. }
procedure TPdfPrintJob.DoBeginDoc;
begin
  Printer.BeginDoc;
  FXDPI := Printer.XDPI;
  FYDPI := Printer.YDPI;
  FPrinterPageWidth := Printer.PageWidth;
  FPrinterPageHeight := Printer.PageHeight;
end;

{ Main thread, via Synchronize - Execute has already released FPdfLock. }
procedure TPdfPrintJob.DoPrintCurrentPage;
var
  bmp: TBitmap;
  {$IFDEF WINDOWS}
  page: FPDF_PAGE;
  {$ENDIF}
begin
  if FPrintedCount > 0 then
    Printer.NewPage;
  {$IFDEF WINDOWS}
  if FEngine = ppeRenderPage then
  begin
    FPdfLock.Enter;
    try
      page := FPDF_LoadPage(FDocHandle, FPageIndex);
      if page = nil then
        raise EPdfiumError.CreateFmt('PdfiumPrint: could not load page %d.', [FPageIndex + 1]);
      try
        FPDF_RenderPage(Printer.Canvas.Handle, page, FDestX, FDestY, FDestWidth, FDestHeight, 0, FPDF_ANNOT);
      finally
        FPDF_ClosePage(page);
      end;
    finally
      FPdfLock.Leave;
    end;
  end
  else
  {$ENDIF}
  begin
    FPdfLock.Enter;
    try
      bmp := PdfiumBitmapToTBitmap(FCurrentBitmap);
    finally
      FPdfLock.Leave;
    end;
    try
      Printer.Canvas.Draw(FDestX, FDestY, bmp);
    finally
      bmp.Free;
    end;
  end;
  Inc(FPrintedCount);
  if Assigned(FOnAfterPagePrint) then
    FOnAfterPagePrint(Self);
end;

{ Main thread, via Synchronize - always the last thing Execute does. }
procedure TPdfPrintJob.DoFinish;
begin
  try
    if (FErrorMessage = '') and (not FCancelled) then
      Printer.EndDoc
    else
      Printer.Abort;
  except
    on E: Exception do
      if FErrorMessage = '' then
        FErrorMessage := E.Message;
  end;
  GPrintJobActive := False;
  if Assigned(FOnAfterDocumentPrint) then
  begin
    try
      FOnAfterDocumentPrint(Self);
    except
      if Assigned(ApplicationHandleException) then
        ApplicationHandleException(Self);
    end;
  end;
end;

procedure TPdfPrintJob.Execute;
var
  i: Integer;
  page: FPDF_PAGE;
begin
  try
    for i := 0 to High(FPages) do
    begin
      if FCancelled then
        break;
      while (PdfiumHighPriorityRequests > 0) and not FCancelled do
        Sleep(5);
      FPageIndex := FPages[i];
      FCurrentBitmap := nil;
      FPdfLock.Enter;
      try
        page := FPDF_LoadPage(FDocHandle, FPageIndex);
        if page = nil then
          raise EPdfiumError.CreateFmt('PdfiumPrint: could not load page %d.', [FPageIndex + 1]);
        try
          ComputePrintRect(FPDF_GetPageWidthF(page), FPDF_GetPageHeightF(page), FOptions.PageSize,
            FOptions.CenterOnPage, FXDPI, FYDPI, FPrinterPageWidth, FPrinterPageHeight,
            FDestX, FDestY, FDestWidth, FDestHeight);
          if FEngine <> ppeRenderPage then
          begin
            FCurrentBitmap := FPDFBitmap_CreateEx(FDestWidth, FDestHeight, FPDFBitmap_BGRA, nil, 0);
            if FCurrentBitmap = nil then
              raise EPdfiumError.Create('PdfiumPrint: could not allocate a print bitmap.');
            FPDFBitmap_FillRect(FCurrentBitmap, 0, 0, FDestWidth, FDestHeight, $FFFFFFFF);
            FPDF_RenderPageBitmap(FCurrentBitmap, page, 0, 0, FDestWidth, FDestHeight, 0, FPDF_ANNOT);
          end;
        finally
          FPDF_ClosePage(page);
        end;
      finally
        FPdfLock.Leave;
      end;
      try
        Synchronize(@DoPrintCurrentPage);
      finally
        if FCurrentBitmap <> nil then
        begin
          FPdfLock.Enter;
          try
            FPDFBitmap_Destroy(FCurrentBitmap);
          finally
            FPdfLock.Leave;
          end;
          FCurrentBitmap := nil;
        end;
      end;
    end;
  except
    on E: Exception do
      FErrorMessage := E.Message;
  end;
  Synchronize(@DoFinish);
end;

function PdfPrintPagesAsync(ADocument: TPdfDocument; const ARanges: array of TPdfPageRange;
  const APages: array of Integer; const AOptions: TPdfPrintOptions;
  AAfterPagePrint: TNotifyEvent = nil; AAfterDocumentPrint: TNotifyEvent = nil): TPdfPrintJob;
var
  finalPages: TIntegerDynArray;
  job: TPdfPrintJob;
begin
  finalPages := CollectPrintPages('PdfPrintPagesAsync', ADocument, ARanges, APages);
  RaiseIfPrintJobActive('PdfPrintPagesAsync');
  SelectPrinterOrRaise(AOptions.PrinterName);
  job := TPdfPrintJob.Create(ADocument, finalPages, AOptions, AAfterPagePrint, AAfterDocumentPrint);
  try
    job.FEngine := ResolveEngine(AOptions.Engine);
    Printer.Copies := AOptions.Copies;
    job.DoBeginDoc;
  except
    job.Free; 
    raise;
  end;
  GPrintJobActive := True;
  job.FreeOnTerminate := True;
  job.Start;
  Result := job;
end;

function PdfPrintPagesAsync(ADocument: TPdfDocument; const APageSpec: String; const AOptions: TPdfPrintOptions;
  AAfterPagePrint: TNotifyEvent = nil; AAfterDocumentPrint: TNotifyEvent = nil): TPdfPrintJob;
var
  pages: TIntegerDynArray;
begin
  if ADocument = nil then
    raise EPdfiumError.Create('PdfPrintPagesAsync: ADocument must not be nil.');
  pages := PdfParsePageSpec(APageSpec, ADocument.PageCount);
  Result := PdfPrintPagesAsync(ADocument, [], pages, AOptions, AAfterPagePrint, AAfterDocumentPrint);
end;

function PdfPrintDocumentAsync(ADocument: TPdfDocument; const AOptions: TPdfPrintOptions;
  AAfterPagePrint: TNotifyEvent = nil; AAfterDocumentPrint: TNotifyEvent = nil): TPdfPrintJob;
begin
  if ADocument = nil then
    raise EPdfiumError.Create('PdfPrintDocumentAsync: ADocument must not be nil.');
  Result := PdfPrintPagesAsync(ADocument, [PdfPageRange(0, ADocument.PageCount - 1)], [], AOptions,
    AAfterPagePrint, AAfterDocumentPrint);
end;

{ TPdfDocumentPrintHelper }

procedure TPdfDocumentPrintHelper.Print(const APrinterName, APageSpec: String; ACopies: Integer = 1);
var
  opts: TPdfPrintOptions;
begin
  opts := PdfDefaultPrintOptions;
  opts.PrinterName := APrinterName;
  opts.Copies := ACopies;
  PdfPrintPages(Self, APageSpec, opts);
end;

procedure TPdfDocumentPrintHelper.Print(const APageSpec: String; const AOptions: TPdfPrintOptions);
begin
  PdfPrintPages(Self, APageSpec, AOptions);
end;

function TPdfDocumentPrintHelper.PrintAsync(const APageSpec: String; const AOptions: TPdfPrintOptions;
  AAfterPagePrint: TNotifyEvent = nil; AAfterDocumentPrint: TNotifyEvent = nil): TPdfPrintJob;
begin
  Result := PdfPrintPagesAsync(Self, APageSpec, AOptions, AAfterPagePrint, AAfterDocumentPrint);
end;

end.
