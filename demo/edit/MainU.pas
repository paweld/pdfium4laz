unit MainU;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls, Spin, ComCtrls, LCLType, LazFileUtils,
  PdfiumLib, PdfiumCore, PdfiumMerge, PdfiumAttachments;

type

  { TMainF }

  TMainF = class(TForm)
    bAttAdd: TButton;
    bAttDelete: TButton;
    bAttExtract: TButton;
    bAttOpen: TButton;
    bAttSave: TButton;
    bMerge: TButton;
    bMergeAdd: TButton;
    bMergeClear: TButton;
    bMergeDown: TButton;
    bMergeRemove: TButton;
    bMergeUp: TButton;
    bMove: TButton;
    bMoveOpen: TButton;
    bMoveSave: TButton;
    bSplit: TButton;
    bSplitOpen: TButton;
    bVerOpen: TButton;
    bVerSave: TButton;
    cbVersion: TComboBox;
    eAttDesc: TEdit;
    eAttSource: TEdit;
    eMoveSource: TEdit;
    eSplitPages: TEdit;
    eSplitSource: TEdit;
    eVerSource: TEdit;
    lAttDesc: TLabel;
    lAttSource: TLabel;
    lMergeInfo: TLabel;
    lMoveAfter: TLabel;
    lMoveAfterHint: TLabel;
    lMoveOrder: TLabel;
    lMovePage: TLabel;
    lMoveSource: TLabel;
    lSplitFrom: TLabel;
    lSplitInfo: TLabel;
    lSplitPages: TLabel;
    lSplitSource: TLabel;
    lSplitTo: TLabel;
    lVerCurrent: TLabel;
    lVerSource: TLabel;
    lVerTarget: TLabel;
    lbMergeFiles: TListBox;
    lbMovePages: TListBox;
    lvAttachments: TListView;
    mLog: TMemo;
    odAny: TOpenDialog;
    odPDF: TOpenDialog;
    pc: TPageControl;
    rgSplitMode: TRadioGroup;
    sdAny: TSaveDialog;
    sdPDF: TSaveDialog;
    sddDir: TSelectDirectoryDialog;
    seMoveAfter: TSpinEdit;
    seMovePage: TSpinEdit;
    seSplitFrom: TSpinEdit;
    seSplitTo: TSpinEdit;
    Splitter1: TSplitter;
    tsAttachments: TTabSheet;
    tsMerge: TTabSheet;
    tsMove: TTabSheet;
    tsSplit: TTabSheet;
    tsVersion: TTabSheet;
    procedure bAttAddClick(Sender: TObject);
    procedure bAttDeleteClick(Sender: TObject);
    procedure bAttExtractClick(Sender: TObject);
    procedure bAttOpenClick(Sender: TObject);
    procedure bAttSaveClick(Sender: TObject);
    procedure bMergeAddClick(Sender: TObject);
    procedure bMergeClearClick(Sender: TObject);
    procedure bMergeClick(Sender: TObject);
    procedure bMergeDownClick(Sender: TObject);
    procedure bMergeRemoveClick(Sender: TObject);
    procedure bMergeUpClick(Sender: TObject);
    procedure bMoveClick(Sender: TObject);
    procedure bMoveOpenClick(Sender: TObject);
    procedure bMoveSaveClick(Sender: TObject);
    procedure bSplitClick(Sender: TObject);
    procedure bSplitOpenClick(Sender: TObject);
    procedure bVerOpenClick(Sender: TObject);
    procedure bVerSaveClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure lbMergeFilesSelectionChange(Sender: TObject; User: Boolean);
    procedure lbMovePagesSelectionChange(Sender: TObject; User: Boolean);
    procedure lvAttachmentsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure rgSplitModeClick(Sender: TObject);
  private
    FLibraryLoaded: Boolean;
    FSplitPageCount: Integer;
    FAttDoc: TPdfDocument;
    FAttList: TPdfAttachmentList;
    FVerDoc: TPdfDocument;
    FMoveDoc: TPdfDocument;
    FMoveOrder: array of Integer;
    procedure Log(const AText: String);
    procedure LogError(const AContext: String; E: Exception);
    procedure UpdateMergeButtons;
    procedure UpdateSplitControls;
    procedure CloseAttDocument;
    procedure LoadAttDocument(const AFileName: String);
    procedure RefreshAttachments;
    procedure UpdateAttButtons;
    procedure CloseVerDocument;
    procedure LoadMoveDocument(const AFileName: String);
    procedure RefreshMovePages;
    function SelectedVersion: Integer;
    procedure SaveDocument(var ADoc: TPdfDocument; const AOutputFile: String; AVersion: Integer);
  public

  end;

var
  MainF: TMainF;

implementation

{$R *.lfm}

const
  {$IFDEF WINDOWS}
  PdfiumLibName = 'pdfium.dll';
  {$ELSE}
  {$IFDEF DARWIN}
  PdfiumLibName = 'libpdfium.dylib';
  {$ELSE}
  PdfiumLibName = 'libpdfium.so';
  {$ENDIF}
  {$ENDIF}
  { Same encoding as TPdfDocument.FileVersion - index matches cbVersion.Items. }
  PdfVersions: array [0..4] of Integer = (14, 15, 16, 17, 20);

function VersionToStr(AVersion: Integer): String;
begin
  if AVersion <= 0 then
    Result := 'unknown'
  else
    Result := Format('%d.%d', [AVersion div 10, AVersion mod 10]);
end;

function SameFile(const A, B: String): Boolean;
begin
  Result := CompareFilenames(ExpandFileName(A), ExpandFileName(B)) = 0;
end;

function ReadFileBytes(const AFileName: String): TBytes;
var
  fs: TFileStream;
begin
  fs := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, fs.Size);
    if Length(Result) > 0 then
      fs.ReadBuffer(Result[0], Length(Result));
  finally
    fs.Free;
  end;
end;

{ Parses a 1-based page list like "1, 3, 5-7" into 0-based page indices. }
function ParsePageList(const AText: String; APageCount: Integer): TIntegerDynArray;
var
  parts: TStringArray;
  part: String;
  dashPos, fromPage, toPage, p, n: Integer;
begin
  Result := nil;
  n := 0;
  parts := AText.Split([',', ';', ' '], TStringSplitOptions.ExcludeEmpty);
  for part in parts do
  begin
    dashPos := Pos('-', part);
    if dashPos > 0 then
    begin
      fromPage := StrToInt(Trim(Copy(part, 1, dashPos - 1)));
      toPage := StrToInt(Trim(Copy(part, dashPos + 1, MaxInt)));
    end
    else
    begin
      fromPage := StrToInt(Trim(part));
      toPage := fromPage;
    end;
    if (fromPage < 1) or (toPage > APageCount) or (toPage < fromPage) then
      raise EConvertError.CreateFmt('Invalid page range "%s" (document has %d pages).', [part, APageCount]);
    SetLength(Result, n + toPage - fromPage + 1);
    for p := fromPage to toPage do
    begin
      Result[n] := p - 1;
      Inc(n);
    end;
  end;
  if n = 0 then
    raise EConvertError.Create('The page list is empty.');
end;

{ TMainF }

procedure TMainF.FormCreate(Sender: TObject);
begin
  FAttDoc := nil;
  FAttList := nil;
  FVerDoc := nil;
  FSplitPageCount := 0;
  pc.ActivePage := tsMerge;
  { The library is normally looked up next to the executable - when that fails
    fall back to the copy shipped with the main demo in ../test. }
  try
    try
      PdfiumInitialize;
    except
      on EPdfiumError do
      begin
        if DirectoryExists(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'view') then
          PdfiumInitialize(ExpandFileName(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'view' + PathDelim + PdfiumLibName));
      end;
    end;
    FLibraryLoaded := True;
    if PdfiumVersion <> '' then
      Log('PDFium loaded, version ' + PdfiumVersion + '.')
    else
      Log('PDFium loaded.');
  except
    on E: Exception do
    begin
      FLibraryLoaded := False;
      LogError('Could not load PDFium', E);
      pc.Enabled := False;
    end;
  end;
  UpdateMergeButtons;
  UpdateSplitControls;
  UpdateAttButtons;
  RefreshMovePages;
end;

procedure TMainF.FormDestroy(Sender: TObject);
begin
  CloseAttDocument;
  CloseVerDocument;
  FreeAndNil(FMoveDoc);
  if FLibraryLoaded then
    PdfiumFinalize;
end;

procedure TMainF.Log(const AText: String);
begin
  mLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + '  ' + AText);
  mLog.SelStart := Length(mLog.Text);
end;

procedure TMainF.LogError(const AContext: String; E: Exception);
begin
  Log('ERROR: ' + AContext + ': ' + E.Message);
  MessageDlg(AContext, E.Message, mtError, [mbOK], 0);
end;

{ Saves ADoc to AOutputFile. PDFium reads a document loaded with LoadFromFile
  lazily, so the source file must stay intact while it is open - saving over
  it goes through a memory stream and reloads the document afterward. }
procedure TMainF.SaveDocument(var ADoc: TPdfDocument; const AOutputFile: String; AVersion: Integer);
var
  ms: TMemoryStream;
  srcFile: String;
begin
  if not SameFile(ADoc.FileName, AOutputFile) then
  begin
    ADoc.SaveToFile(AOutputFile, AVersion);
    exit;
  end;
  srcFile := ADoc.FileName;
  ms := TMemoryStream.Create;
  try
    ADoc.SaveToStream(ms, AVersion);
    ADoc.Close;
    ms.SaveToFile(AOutputFile);
  finally
    ms.Free;
  end;
  ADoc.LoadFromFile(srcFile);
end;

procedure TMainF.UpdateMergeButtons;
var
  idx: Integer;
begin
  idx := lbMergeFiles.ItemIndex;
  bMergeRemove.Enabled := idx >= 0;
  bMergeUp.Enabled := idx > 0;
  bMergeDown.Enabled := (idx >= 0) and (idx < lbMergeFiles.Count - 1);
  bMergeClear.Enabled := lbMergeFiles.Count > 0;
  bMerge.Enabled := lbMergeFiles.Count > 1;
  lMergeInfo.Caption := Format('Files to merge (in this order): %d', [lbMergeFiles.Count]);
end;

procedure TMainF.lbMergeFilesSelectionChange(Sender: TObject; User: Boolean);
begin
  UpdateMergeButtons;
end;

procedure TMainF.lbMovePagesSelectionChange(Sender: TObject; User: Boolean);
begin
  if User and (lbMovePages.ItemIndex >= 0) then
    seMovePage.Value := lbMovePages.ItemIndex + 1;
end;

procedure TMainF.bMergeAddClick(Sender: TObject);
begin
  odPDF.Options := odPDF.Options + [ofAllowMultiSelect];
  try
    if not odPDF.Execute then
      exit;
    lbMergeFiles.Items.AddStrings(odPDF.Files);
  finally
    odPDF.Options := odPDF.Options - [ofAllowMultiSelect];
  end;
  if lbMergeFiles.ItemIndex < 0 then
    lbMergeFiles.ItemIndex := 0;
  UpdateMergeButtons;
end;

procedure TMainF.bMergeRemoveClick(Sender: TObject);
var
  idx: Integer;
begin
  idx := lbMergeFiles.ItemIndex;
  if idx < 0 then
    exit;
  lbMergeFiles.Items.Delete(idx);
  if idx >= lbMergeFiles.Count then
    idx := lbMergeFiles.Count - 1;
  lbMergeFiles.ItemIndex := idx;
  UpdateMergeButtons;
end;

procedure TMainF.bMergeUpClick(Sender: TObject);
var
  idx: Integer;
begin
  idx := lbMergeFiles.ItemIndex;
  if idx <= 0 then
    exit;
  lbMergeFiles.Items.Exchange(idx, idx - 1);
  lbMergeFiles.ItemIndex := idx - 1;
  UpdateMergeButtons;
end;

procedure TMainF.bMoveClick(Sender: TObject);
var
  page, after, destIndex, i, moved: Integer;
begin
  if FMoveDoc = nil then
    exit;
  page := seMovePage.Value;
  after := seMoveAfter.Value;
  if (page = after) or (page = after + 1) then
  begin
    Log(Format('Page %d is already right after page %d - nothing to move.', [page, after]));
    exit;
  end;
  { MovePages takes the destination as an index in the document AFTER the
    move - when the page moves forward, removing it from its old position
    shifts every following page one place back. }
  if page < after then
    destIndex := after - 1
  else
    destIndex := after;
  try
    FMoveDoc.MovePages([page - 1], destIndex);
  except
    on E: Exception do
    begin
      LogError('Could not move the page', E);
      exit;
    end;
  end;
  moved := FMoveOrder[page - 1];
  if page - 1 < destIndex then
    for i := page - 1 to destIndex - 1 do
      FMoveOrder[i] := FMoveOrder[i + 1]
  else
    for i := page - 1 downto destIndex + 1 do
      FMoveOrder[i] := FMoveOrder[i - 1];
  FMoveOrder[destIndex] := moved;
  if after = 0 then
    Log(Format('Moved page %d to the beginning - use "Save PDF as..." to write the document.', [page]))
  else
    Log(Format('Moved page %d after page %d - it is now page %d. Use "Save PDF as..." to write the document.',
      [page, after, destIndex + 1]));
  RefreshMovePages;
  lbMovePages.ItemIndex := destIndex;
end;

procedure TMainF.bMoveOpenClick(Sender: TObject);
begin
  if not odPDF.Execute then
    exit;
  eMoveSource.Text := '';
  try
    LoadMoveDocument(odPDF.FileName);
    eMoveSource.Text := odPDF.FileName;
    seMovePage.Value := 1;
    seMoveAfter.Value := 0;
    Log(Format('Move source: "%s" (%d pages).', [odPDF.FileName, FMoveDoc.PageCount]));
  except
    on E: Exception do
      LogError('Could not open "' + odPDF.FileName + '"', E);
  end;
  RefreshMovePages;
end;

procedure TMainF.bMoveSaveClick(Sender: TObject);
var
  outFile: String;
begin
  if FMoveDoc = nil then
    exit;
  sdPDF.Title := 'Save reordered PDF as';
  sdPDF.FileName := ChangeFileExt(ExtractFileName(FMoveDoc.FileName), '') + '_reordered.pdf';
  if not sdPDF.Execute then
    exit;
  outFile := sdPDF.FileName;
  try
    SaveDocument(FMoveDoc, outFile, 0);
    Log(Format('Saved "%s".', [outFile]));
    { Continue working on the saved file - page numbers start fresh from it. }
    LoadMoveDocument(outFile);
    eMoveSource.Text := outFile;
  except
    on E: Exception do
      LogError('Could not save "' + outFile + '"', E);
  end;
  RefreshMovePages;
end;

procedure TMainF.bMergeDownClick(Sender: TObject);
var
  idx: Integer;
begin
  idx := lbMergeFiles.ItemIndex;
  if (idx < 0) or (idx >= lbMergeFiles.Count - 1) then
    exit;
  lbMergeFiles.Items.Exchange(idx, idx + 1);
  lbMergeFiles.ItemIndex := idx + 1;
  UpdateMergeButtons;
end;

procedure TMainF.bMergeClearClick(Sender: TObject);
begin
  lbMergeFiles.Clear;
  UpdateMergeButtons;
end;

procedure TMainF.bMergeClick(Sender: TObject);
var
  sources: array of String;
  i: Integer;
begin
  if lbMergeFiles.Count < 2 then
    exit;
  sdPDF.Title := 'Save merged PDF as';
  sdPDF.FileName := 'merged.pdf';
  if not sdPDF.Execute then
    exit;
  SetLength(sources, lbMergeFiles.Count);
  for i := 0 to lbMergeFiles.Count - 1 do
  begin
    sources[i] := lbMergeFiles.Items[i];
    if SameFile(sources[i], sdPDF.FileName) then
    begin
      MessageDlg('Merge', 'The output file must not be one of the source files.', mtWarning, [mbOK], 0);
      exit;
    end;
  end;
  Screen.Cursor := crHourGlass;
  try
    try
      PdfMergeFiles(sources, sdPDF.FileName);
      Log(Format('Merged %d files into "%s".', [Length(sources), sdPDF.FileName]));
    except
      on E: Exception do
        LogError('Merge failed', E);
    end;
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TMainF.UpdateSplitControls;
var
  hasDoc: Boolean;
begin
  hasDoc := FSplitPageCount > 0;
  rgSplitMode.Enabled := hasDoc;
  seSplitFrom.Enabled := hasDoc and (rgSplitMode.ItemIndex = 1);
  seSplitTo.Enabled := hasDoc and (rgSplitMode.ItemIndex = 1);
  eSplitPages.Enabled := hasDoc and (rgSplitMode.ItemIndex = 2);
  bSplit.Enabled := hasDoc;
  if hasDoc then
    lSplitInfo.Caption := Format('Pages: %d', [FSplitPageCount])
  else
    lSplitInfo.Caption := 'Pages: -';
end;

procedure TMainF.rgSplitModeClick(Sender: TObject);
begin
  UpdateSplitControls;
end;

procedure TMainF.bSplitOpenClick(Sender: TObject);
var
  doc: TPdfDocument;
begin
  if not odPDF.Execute then
    exit;
  FSplitPageCount := 0;
  eSplitSource.Text := '';
  doc := TPdfDocument.Create;
  try
    try
      doc.LoadFromFile(odPDF.FileName);
      FSplitPageCount := doc.PageCount;
      eSplitSource.Text := odPDF.FileName;
      Log(Format('Split source: "%s" (%d pages).', [odPDF.FileName, FSplitPageCount]));
    except
      on E: Exception do
        LogError('Could not open "' + odPDF.FileName + '"', E);
    end;
  finally
    doc.Free;
  end;
  seSplitFrom.MaxValue := Max(FSplitPageCount, 1);
  seSplitTo.MaxValue := Max(FSplitPageCount, 1);
  seSplitFrom.Value := 1;
  seSplitTo.Value := Max(FSplitPageCount, 1);
  if FSplitPageCount > 0 then
    eSplitPages.Text := '1-' + IntToStr(FSplitPageCount);
  UpdateSplitControls;
end;

procedure TMainF.bSplitClick(Sender: TObject);
var
  pages: TIntegerDynArray;
  i: Integer;
  srcStream, destStream: TFileStream;
  baseName: String;
begin
  if FSplitPageCount <= 0 then
    exit;
  baseName := ChangeFileExt(ExtractFileName(eSplitSource.Text), '');
  try
    case rgSplitMode.ItemIndex of
      0:
      begin
        sddDir.Title := 'Select the output folder';
        sddDir.InitialDir := ExtractFilePath(eSplitSource.Text);
        if not sddDir.Execute then
          exit;
        SetLength(pages, FSplitPageCount);
        for i := 0 to FSplitPageCount - 1 do
          pages[i] := i;
        Screen.Cursor := crHourGlass;
        try
          PdfSplitPages(eSplitSource.Text, sddDir.FileName, pages);
        finally
          Screen.Cursor := crDefault;
        end;
        Log(Format('Split %d pages into separate files in "%s".', [FSplitPageCount, sddDir.FileName]));
      end;
      1:
      begin
        if seSplitTo.Value < seSplitFrom.Value then
          raise EConvertError.Create('"To" page must not be less than "From" page.');
        sdPDF.Title := 'Save page range as';
        sdPDF.FileName := Format('%s_%d-%d.pdf', [baseName, seSplitFrom.Value, seSplitTo.Value]);
        if not sdPDF.Execute then
          exit;
        if SameFile(sdPDF.FileName, eSplitSource.Text) then
          raise EConvertError.Create('The output file must not be the source file.');
        PdfSplitRange(eSplitSource.Text, sdPDF.FileName, seSplitFrom.Value - 1, seSplitTo.Value - 1);
        Log(Format('Saved pages %d-%d to "%s".', [seSplitFrom.Value, seSplitTo.Value, sdPDF.FileName]));
      end;
      2:
      begin
        pages := ParsePageList(eSplitPages.Text, FSplitPageCount);
        sdPDF.Title := 'Save selected pages as';
        sdPDF.FileName := baseName + '_selected.pdf';
        if not sdPDF.Execute then
          exit;
        if SameFile(sdPDF.FileName, eSplitSource.Text) then
          raise EConvertError.Create('The output file must not be the source file.');
        { Stream variant - pages are taken in the order given, duplicates allowed. }
        srcStream := TFileStream.Create(eSplitSource.Text, fmOpenRead or fmShareDenyWrite);
        try
          destStream := TFileStream.Create(sdPDF.FileName, fmCreate);
          try
            PdfSplitToStream(srcStream, pages, destStream);
          finally
            destStream.Free;
          end;
        finally
          srcStream.Free;
        end;
        Log(Format('Saved %d selected pages (%s) to "%s".', [Length(pages), eSplitPages.Text, sdPDF.FileName]));
      end;
    end;
  except
    on E: Exception do
      LogError('Split failed', E);
  end;
end;

procedure TMainF.CloseAttDocument;
begin
  FreeAndNil(FAttList);
  FreeAndNil(FAttDoc);
end;

procedure TMainF.LoadAttDocument(const AFileName: String);
begin
  CloseAttDocument;
  FAttDoc := TPdfDocument.Create;
  try
    FAttDoc.LoadFromFile(AFileName);
  except
    FreeAndNil(FAttDoc);
    raise;
  end;
  FAttList := TPdfAttachmentList.Create(FAttDoc);
end;

procedure TMainF.RefreshAttachments;
var
  i: Integer;
  item: TListItem;
begin
  lvAttachments.Items.BeginUpdate;
  try
    lvAttachments.Items.Clear;
    if FAttList <> nil then
    begin
      for i := 0 to FAttList.Count - 1 do
      begin
        item := lvAttachments.Items.Add;
        item.Caption := FAttList[i].Name;
        item.SubItems.Add(Format('%.1f kB', [FAttList[i].Size / 1024]));
        item.SubItems.Add(FAttList[i].Description);
        item.SubItems.Add(FAttList[i].CreationDate);
      end;
    end;
  finally
    lvAttachments.Items.EndUpdate;
  end;
  UpdateAttButtons;
end;

procedure TMainF.UpdateAttButtons;
var
  hasDoc, hasSel: Boolean;
begin
  hasDoc := FAttList <> nil;
  hasSel := hasDoc and (lvAttachments.Selected <> nil);
  bAttAdd.Enabled := hasDoc;
  eAttDesc.Enabled := hasDoc;
  bAttDelete.Enabled := hasSel;
  bAttExtract.Enabled := hasSel;
  bAttSave.Enabled := hasDoc;
end;

procedure TMainF.lvAttachmentsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  UpdateAttButtons;
end;

procedure TMainF.bAttOpenClick(Sender: TObject);
begin
  if not odPDF.Execute then
    exit;
  try
    LoadAttDocument(odPDF.FileName);
    eAttSource.Text := odPDF.FileName;
    Log(Format('Attachments source: "%s" (%d attachments).', [odPDF.FileName, FAttList.Count]));
  except
    on E: Exception do
    begin
      eAttSource.Text := '';
      LogError('Could not open "' + odPDF.FileName + '"', E);
    end;
  end;
  RefreshAttachments;
end;

procedure TMainF.bAttAddClick(Sender: TObject);
var
  item: TPdfAttachmentItem;
  attName: String;
begin
  if (FAttList = nil) or not odAny.Execute then
    exit;
  attName := ExtractFileName(odAny.FileName);
  try
    item := FAttList.Add(attName);
    item.SetData(ReadFileBytes(odAny.FileName));
    if eAttDesc.Text <> '' then
      item.SetDescription(eAttDesc.Text);
    item.SetStringValue(PDF_ATTACHMENT_KEY_CREATIONDATE, FormatDateTime('"D:"yyyymmddhhnnss', Now));
    Log(Format('Added attachment "%s" (%d bytes) - use "Save PDF as..." to write the document.',
      [attName, item.Size]));
  except
    on E: Exception do
      LogError('Could not add attachment "' + attName + '"', E);
  end;
  RefreshAttachments;
end;

procedure TMainF.bAttDeleteClick(Sender: TObject);
var
  idx: Integer;
  attName: String;
begin
  if (FAttList = nil) or (lvAttachments.Selected = nil) then
    exit;
  idx := lvAttachments.Selected.Index;
  attName := FAttList[idx].Name;
  try
    FAttList.Delete(idx);
    Log(Format('Deleted attachment "%s" - use "Save PDF as..." to write the document.', [attName]));
  except
    on E: Exception do
      LogError('Could not delete attachment "' + attName + '"', E);
  end;
  RefreshAttachments;
end;

procedure TMainF.bAttExtractClick(Sender: TObject);
var
  item: TPdfAttachmentItem;
begin
  if (FAttList = nil) or (lvAttachments.Selected = nil) then
    exit;
  item := FAttList[lvAttachments.Selected.Index];
  sdAny.FileName := item.Name;
  if not sdAny.Execute then
    exit;
  try
    item.SaveToFile(sdAny.FileName);
    Log(Format('Extracted attachment "%s" to "%s".', [item.Name, sdAny.FileName]));
  except
    on E: Exception do
      LogError('Could not extract attachment "' + item.Name + '"', E);
  end;
end;

procedure TMainF.bAttSaveClick(Sender: TObject);
var
  outFile: String;
begin
  if FAttDoc = nil then
    exit;
  sdPDF.Title := 'Save PDF with attachments as';
  sdPDF.FileName := ChangeFileExt(ExtractFileName(FAttDoc.FileName), '') + '_attachments.pdf';
  if not sdPDF.Execute then
    exit;
  outFile := sdPDF.FileName;
  try
    { Attachment handles do not survive a reload - drop the list first. }
    FreeAndNil(FAttList);
    SaveDocument(FAttDoc, outFile, 0);
    Log(Format('Saved "%s".', [outFile]));
    { Reopen the saved file so the list shows what actually got written. }
    LoadAttDocument(outFile);
    eAttSource.Text := outFile;
  except
    on E: Exception do
      LogError('Could not save "' + outFile + '"', E);
  end;
  if (FAttDoc <> nil) and (FAttList = nil) then
    FAttList := TPdfAttachmentList.Create(FAttDoc);
  RefreshAttachments;
end;

procedure TMainF.CloseVerDocument;
begin
  FreeAndNil(FVerDoc);
end;

procedure TMainF.LoadMoveDocument(const AFileName: String);
var
  i: Integer;
begin
  FreeAndNil(FMoveDoc);
  FMoveDoc := TPdfDocument.Create;
  try
    FMoveDoc.LoadFromFile(AFileName);
  except
    FreeAndNil(FMoveDoc);
    raise;
  end;
  SetLength(FMoveOrder, FMoveDoc.PageCount);
  for i := 0 to High(FMoveOrder) do
    FMoveOrder[i] := i + 1;
end;

procedure TMainF.RefreshMovePages;
var
  i, pageCount: Integer;
begin
  if FMoveDoc = nil then
    pageCount := 0
  else
    pageCount := FMoveDoc.PageCount;
  lbMovePages.Items.BeginUpdate;
  try
    lbMovePages.Items.Clear;
    for i := 0 to pageCount - 1 do
    begin
      if FMoveOrder[i] = i + 1 then
        lbMovePages.Items.Add(Format('Page %d', [i + 1]))
      else
        lbMovePages.Items.Add(Format('Page %d   (originally page %d)', [i + 1, FMoveOrder[i]]));
    end;
  finally
    lbMovePages.Items.EndUpdate;
  end;
  seMovePage.MaxValue := Max(pageCount, 1);
  seMoveAfter.MaxValue := pageCount;
  seMovePage.Enabled := pageCount > 1;
  seMoveAfter.Enabled := pageCount > 1;
  bMove.Enabled := pageCount > 1;
  bMoveSave.Enabled := pageCount > 0;
  lMoveOrder.Caption := Format('Current page order (%d pages):', [pageCount]);
end;

function TMainF.SelectedVersion: Integer;
begin
  if cbVersion.ItemIndex < 0 then
    Result := 17
  else
    Result := PdfVersions[cbVersion.ItemIndex];
end;

procedure TMainF.bVerOpenClick(Sender: TObject);
begin
  if not odPDF.Execute then
    exit;
  CloseVerDocument;
  eVerSource.Text := '';
  lVerCurrent.Caption := 'Current version: -';
  bVerSave.Enabled := False;
  FVerDoc := TPdfDocument.Create;
  try
    FVerDoc.LoadFromFile(odPDF.FileName);
    eVerSource.Text := odPDF.FileName;
    lVerCurrent.Caption := 'Current version: PDF ' + VersionToStr(FVerDoc.FileVersion);
    bVerSave.Enabled := True;
    Log(Format('Version source: "%s" (PDF %s).', [odPDF.FileName, VersionToStr(FVerDoc.FileVersion)]));
  except
    on E: Exception do
    begin
      CloseVerDocument;
      LogError('Could not open "' + odPDF.FileName + '"', E);
    end;
  end;
end;

procedure TMainF.bVerSaveClick(Sender: TObject);
var
  version: Integer;
  check: TPdfDocument;
begin
  if FVerDoc = nil then
    exit;
  version := SelectedVersion;
  sdPDF.Title := 'Save as PDF ' + VersionToStr(version);
  sdPDF.FileName := Format('%s_pdf%d.pdf', [ChangeFileExt(ExtractFileName(FVerDoc.FileName), ''), version]);
  if not sdPDF.Execute then
    exit;
  try
    SaveDocument(FVerDoc, sdPDF.FileName, version);
    { Reopen the written file to show which version actually ended up in it. }
    check := TPdfDocument.Create;
    try
      check.LoadFromFile(sdPDF.FileName);
      Log(Format('Saved "%s" as PDF %s (file reports PDF %s).',
        [sdPDF.FileName, VersionToStr(version), VersionToStr(check.FileVersion)]));
    finally
      check.Free;
    end;
    lVerCurrent.Caption := 'Current version: PDF ' + VersionToStr(FVerDoc.FileVersion);
  except
    on E: Exception do
      LogError('Could not save "' + sdPDF.FileName + '"', E);
  end;
end;

end.
