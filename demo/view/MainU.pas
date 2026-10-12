unit MainU;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls, Spin, LCLIntf, Math,
  fgl, Types, LCLType, ComCtrls, StrUtils, LazVersion, LCLPlatformDef, InterfaceBase, {$IFDEF DEBUG}LineInfo,{$ENDIF}
  PdfiumCore, PdfiumLib, PdfiumViewer, PdfiumLinks, PdfiumThumbnails, PdfiumBookmarks, PdfiumText,
  PdfiumImages, PdfiumAttachments;

type

  { TMainF }

  TMainF = class(TForm)
    bSaveAtt: TButton;
    bZoomAuto: TButton;
    bZoomIn: TButton;
    bOpen: TButton;
    bZoomOut: TButton;
    bGetText: TButton;
    bShowAtt: TButton;
    bShowImg: TButton;
    bSaveImg: TButton;
    bSearch: TButton;
    bSearchPrev: TButton;
    bSaveAsImage: TButton;
    bPrint: TButton;
    chbMatchCase: TCheckBox;
    chbCenter: TCheckBox;
    chbShowThumb: TCheckBox;
    cbZoomMode: TComboBox;
    clbTSColor: TColorButton;
    clbBGColor: TColorButton;
    chbUCSEnable: TCheckBox;
    clbUCSbg: TColorButton;
    clbUCStf: TColorButton;
    clbUCSts: TColorButton;
    clbUCSpf: TColorButton;
    clbUCSps: TColorButton;
    ePageCount: TEdit;
    eSearch: TEdit;
    gbUCS: TGroupBox;
    Label1: TLabel;
    Label2: TLabel;
    bNext: TButton;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    lInfo: TLabel;
    lbAttachments: TListBox;
    lbImages: TListBox;
    odPDF: TOpenDialog;
    sdSave: TSaveDialog;
    Panel2: TPanel;
    Panel4: TPanel;
    Panel5: TPanel;
    pc: TPageControl;
    Panel1: TPanel;
    Panel3: TPanel;
    bPrev: TButton;
    PdfThumbnailPanel1: TPdfThumbnailPanel;
    PdfViewer1: TPdfViewer;
    sePageNo: TSpinEdit;
    bClose: TButton;
    seTSAlpha: TSpinEdit;
    Splitter1: TSplitter;
    tvBookmarks: TTreeView;
    tsAttachments: TTabSheet;
    tsImages: TTabSheet;
    tsThumbnails: TTabSheet;
    tsBookmarks: TTabSheet;
    procedure bCloseClick(Sender: TObject);
    procedure bGetTextClick(Sender: TObject);
    procedure bNextClick(Sender: TObject);
    procedure bOpenClick(Sender: TObject);
    procedure bPrevClick(Sender: TObject);
    procedure bPrintClick(Sender: TObject);
    procedure bSaveAsImageClick(Sender: TObject);
    procedure bSaveAttClick(Sender: TObject);
    procedure bSaveImgClick(Sender: TObject);
    procedure bZoomAutoClick(Sender: TObject);
    procedure bZoomOutClick(Sender: TObject);
    procedure bZoomInClick(Sender: TObject);
    procedure bSearchClick(Sender: TObject);
    procedure bSearchPrevClick(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure eSearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure bShowAttClick(Sender: TObject);
    procedure bShowImgClick(Sender: TObject);
    procedure chbUCSEnableChange(Sender: TObject);
    procedure clbColorChanged(Sender: TObject);
    procedure chbCenterChange(Sender: TObject);
    procedure chbShowThumbChange(Sender: TObject);
    procedure cbZoomModeChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure PdfThumbnailPanel1PageCaption(Sender: TObject; APageIndex: Integer; var ACaption: String);
    procedure PdfThumbnailPanel1PageClick(Sender: TObject; APageIndex: Integer);
    procedure PdfViewer1LinkClick(Sender: TObject; const ALink: TPdfLink);
    procedure PdfViewer1LinkEnter(Sender: TObject; const ALink: TPdfLink);
    procedure PdfViewer1LinkLeave(Sender: TObject; const ALink: TPdfLink);
    procedure PdfViewer1MouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure PdfViewer1PageChanged(Sender: TObject);
    procedure sePageNoChange(Sender: TObject);
    procedure seTSAlphaChange(Sender: TObject);
    procedure tvBookmarksSelectionChanged(Sender: TObject);
    procedure tvBookmarksAdvancedCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode;
      State: TCustomDrawState; Stage: TCustomDrawStage; var PaintImages, DefaultDraw: Boolean);
  private
    FPdfDoc: TPdfDocument;
  private
    {$IFDEF DEBUG}procedure LogException(Sender: TObject; E: Exception);{$ENDIF}
    procedure AutoZoomPage;
    function SearchInDocument(AText: String; ABackward: Boolean = False): Boolean;
    procedure RunSearch(ABackward: Boolean);
    procedure ResetSearch;
    procedure LoadBookmarks;
    function BookmarkOfNode(ANode: TTreeNode): TPdfBookmark;
    procedure SyncBookmarkToPage(APageIndex: Integer);
    procedure LoadImages;
    procedure LoadAttachments;
  public
    property PdfDoc: TPdfDocument read FPdfDoc;
  end;

var
  MainF: TMainF;

implementation

{$R *.lfm}

{ TMainF }

uses
  TextU, ImageU, AttachmentU, PrintU;

const
  PageCaptionArr: array [0..87] of String = ('page', 'strona', 'bladsy', 'bladzijde', 'bogga', 'duilleag', 'faqe',
    'halaman', 'ikhasi', 'iphepha', 'itulau', 'iwe', 'kaca', 'lappuse', 'leathanach', 'lehele', 'leqephe', 'nplooj ntawv',
    'oldalt', 'orrialdea', 'pagina', 'pahina', 'paj', 'panid', 'paĝo', 'paġna', 'peeji', 'peji', 'pejy', 'puslapis',
    'página', 'páxina', 'rûpel', 'sahifa', 'sayfa', 'seite', 'shafi', 'sida', 'side', 'sivu', 'strana', 'strani',
    'stranica', 'stránke', 'säit', 'síðu', 'səhifə', 'trang', 'tsamba', 'tudalen', 'ukurasa', 'whaarangi',
    'ʻaoʻao', 'σελίδα', 'бет', 'саҳифа', 'старонка', 'сторінки', 'страна', 'страница', 'хуудас', 'էջ',
    'זייַט', 'עמוד', 'الصفحة', 'صفحه', 'صفحو', 'صفحہ', 'مخ', 'पृष्ठ', 'পৃষ্ঠা', 'ਪੇਜ', 'પાનું', 'பக்கம்', 'పేజీ', 'ಪುಟ',
    'പേജ്', 'පිටුව', 'หน้า', 'ຫນ້າ', 'စာမျက်နှာ', 'გვერდი', 'ገጽ', 'ទំព័រ', 'ページ', '頁', '页', '페이지');
  ImageSaveFilter = 'PNG image (*.png)|*.png|JPEG image (*.jpg)|*.jpg;*.jpeg|Bitmap (*.bmp)|*.bmp';

var
  FBookmarks: TPdfBookmarkTree = nil;
  FBookmarkSyncing: Boolean = False;
  FBookmarkPageWidth: Integer = 0;
  FSearchInstance: TPdfSearch = nil;
  FSearchTextPage: TPdfTextPage = nil;
  FLastSearchedText: String = '';
  FSearchPageIndex: Integer = 0;
  FSearchFlags: TPdfSearchFlags = [];

function ListItemFileName(const ACaption: String): String;
var
  i: Integer;
begin
  Result := ACaption;
  for i := Length(Result) - 1 downto 1 do
  begin
    if (Result[i] = ' ') and (Result[i + 1] = '(') then
    begin
      SetLength(Result, i - 1);
      break;
    end;
  end;
  Result := TrimRight(Result);
  for i := 1 to Length(Result) do
  begin
    if Result[i] in [#0..#31, '/', '\', ':', '*', '?', '"', '<', '>', '|'] then
      Result[i] := '_';
  end;
  if Result = '' then
    Result := 'unnamed';
end;

procedure TMainF.FormCreate(Sender: TObject);
var
  lv: String;
begin
  lv := IntToStr(laz_major) + '.' + IntToStr(laz_minor);
  if laz_release <> 0 then
    lv := lv + '.' + IntToStr(laz_release);
  lInfo.Caption := Format('Widgsetset: %s; Lazarus: %s; FPC: %s; %s-%s',
    [LCLPlatformDirNames[WidgetSet.LCLPlatform], lv, {$I %FPCVERSION%}, {$I %FPCTARGETOS%}, {$I %FPCTARGETCPU%}]);
  {$IFDEF DEBUG}Application.OnException := @LogException;{$ENDIF}
  if chbShowThumb.Checked then
    pc.ActivePage := tsThumbnails
  else
    pc.ActivePage := tsBookmarks;
  FPdfDoc := nil;
  clbTSColor.ButtonColor := PdfViewer1.SelectionColor;
  seTSAlpha.Value := PdfViewer1.SelectionAlpha;
  clbBGColor.ButtonColor := PdfViewer1.BackgroundColor;
  clbUCSbg.ButtonColor := PdfViewer1.SchemeBackgroundColor;
  clbUCStf.ButtonColor := PdfViewer1.SchemeTextFillColor;
  clbUCSts.ButtonColor := PdfViewer1.SchemeTextStrokeColor;
  clbUCSpf.ButtonColor := PdfViewer1.SchemePathFillColor;
  clbUCSps.ButtonColor := PdfViewer1.SchemePathStrokeColor;
  chbUCSEnable.Checked := PdfViewer1.UseColorScheme;
end;

procedure TMainF.FormDestroy(Sender: TObject);
begin
  ResetSearch;
  if FPdfDoc <> nil then
  begin
    FreeAndNil(FBookmarks);
    PdfThumbnailPanel1.Document := nil;
    PdfViewer1.Document := nil;
    FreeAndNil(FPdfDoc);
  end;
end;

procedure TMainF.PdfThumbnailPanel1PageCaption(Sender: TObject; APageIndex: Integer; var ACaption: String);
var
  lbl: String = '';
begin
  lbl := Trim(FPdfDoc.PageLabel(APageIndex));
  if lbl <> '' then
    lbl := ' (' + lbl + ')';
  ACaption := PageCaptionArr[APageIndex mod Length(PageCaptionArr)] + ' ' + IntToStr(APageIndex + 1) + lbl;
end;

procedure TMainF.PdfThumbnailPanel1PageClick(Sender: TObject; APageIndex: Integer);
begin
  PdfViewer1.GotoPage(APageIndex);
end;

procedure TMainF.PdfViewer1LinkClick(Sender: TObject; const ALink: TPdfLink);
begin
  case ALink.Kind of
    lkURI: OpenURL(ALink.URI);
    lkGoto:
      begin
        if ALink.PageIndex >= 0 then
          PdfViewer1.GotoPage(ALink.PageIndex);
      end;
  end;
end;

procedure TMainF.PdfViewer1LinkEnter(Sender: TObject; const ALink: TPdfLink);
begin
  PdfViewer1.Cursor := crHandPoint;
end;

procedure TMainF.PdfViewer1LinkLeave(Sender: TObject; const ALink: TPdfLink);
begin
  PdfViewer1.Cursor := crDefault;
end;

procedure TMainF.PdfViewer1MouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
end;

procedure TMainF.PdfViewer1PageChanged(Sender: TObject);
begin
  PdfThumbnailPanel1.SelectedIndex := PdfViewer1.PageIndex;
  PdfThumbnailPanel1.ScrollToPage(PdfViewer1.PageIndex);
  SyncBookmarkToPage(PdfViewer1.PageIndex);
end;

procedure TMainF.bPrevClick(Sender: TObject);
begin
  PdfViewer1.GotoPage(PdfViewer1.PageIndex - 1);
  sePageNo.Value := PdfViewer1.PageIndex + 1;
end;

procedure TMainF.bPrintClick(Sender: TObject);
begin
  if FPdfDoc = nil then
    exit;
  Application.CreateForm(TPrintF, PrintF);
  PrintF.Document := FPdfDoc;
  PrintF.CurrentPage := PdfViewer1.PageIndex;
  PrintF.ShowModal;
  FreeAndNil(PrintF);
end;

procedure TMainF.bSaveImgClick(Sender: TObject);
var
  Images: TPdfImageList;
begin
  if (lbImages.ItemIndex < 0) or (FPdfDoc = nil) then
    exit;
  sdSave.Title := 'Save image';
  sdSave.Filter := ImageSaveFilter;
  sdSave.FilterIndex := 1;
  sdSave.DefaultExt := '.png';
  sdSave.FileName := ListItemFileName(lbImages.Items[lbImages.ItemIndex]) + '.png';
  if not sdSave.Execute then
    exit;
  Images := TPdfImageList.CreateForDocument(FPdfDoc);
  try
    try
      Images[PtrInt(lbImages.Items.Objects[lbImages.ItemIndex])].SaveToFile(sdSave.FileName);
    except
      on E: Exception do
        ShowMessage('Could not save image to "' + sdSave.FileName + '": ' + E.Message);
    end;
  finally
    Images.Free;
  end;
end;

procedure TMainF.bSaveAsImageClick(Sender: TObject);
var
  page: TPdfPage;
  bmp: TBitmap;
  pic: TPicture;
begin
  if FPdfDoc = nil then
    exit;
  sdSave.Title := 'Save page as image';
  sdSave.Filter := ImageSaveFilter;
  sdSave.FilterIndex := 1;
  sdSave.DefaultExt := '.png';
  sdSave.FileName := Format('%s - page %d.png', [ChangeFileExt(ExtractFileName(FPdfDoc.FileName), ''), PdfViewer1.PageIndex + 1]);
  if not sdSave.Execute then
    exit;
  page := FPdfDoc.Pages[PdfViewer1.PageIndex];
  bmp := nil;
  Screen.Cursor := crHourGlass;
  pic := TPicture.Create;
  try
    try
      bmp := page.RenderToBitmap(Max(1, Round(page.Width * 150 / 72)), Max(1, Round(page.Height * 150 / 72)));
      pic.Bitmap.Assign(bmp);
      case LowerCase(ExtractFileExt(sdSave.FileName)) of
        '.bmp': pic.Bitmap.SaveToFile(sdSave.FileName);
        '.jpg', '.jpeg': pic.Jpeg.SaveToFile(sdSave.FileName);
        else
          pic.PNG.SaveToFile(sdSave.FileName);
      end;
    except
      on E: Exception do
        ShowMessage('Could not save page to "' + sdSave.FileName + '": ' + E.Message);
    end;
  finally
    bmp.Free;
    pic.Free;
    Screen.Cursor := crDefault;
  end;
end;

procedure TMainF.bSaveAttClick(Sender: TObject);
var
  Attachments: TPdfAttachmentList;
begin
  if (lbAttachments.ItemIndex < 0) or (FPdfDoc = nil) then
    exit;
  sdSave.Title := 'Save attachment';
  sdSave.Filter := 'All files|*';
  sdSave.FilterIndex := 1;
  sdSave.DefaultExt := '';
  sdSave.FileName := ListItemFileName(lbAttachments.Items[lbAttachments.ItemIndex]);
  if not sdSave.Execute then
    exit;
  Attachments := TPdfAttachmentList.Create(FPdfDoc);
  try
    try
      Attachments[PtrInt(lbAttachments.Items.Objects[lbAttachments.ItemIndex])].SaveToFile(sdSave.FileName);
    except
      on E: Exception do
        ShowMessage('Could not save attachment to "' + sdSave.FileName + '": ' + E.Message);
    end;
  finally
    Attachments.Free;
  end;
end;

procedure TMainF.bZoomAutoClick(Sender: TObject);
begin
  AutoZoomPage;
end;

procedure TMainF.bZoomOutClick(Sender: TObject);
begin
  if PdfViewer1.Zoom > 0.2501 then
    PdfViewer1.ZoomOut(0.05);
end;

procedure TMainF.bZoomInClick(Sender: TObject);
begin
  if PdfViewer1.Zoom < 4.0001 then
    PdfViewer1.ZoomIn(0.05);
end;

procedure TMainF.RunSearch(ABackward: Boolean);
begin
  if (FPdfDoc = nil) or (eSearch.Text = '') then
    exit;
  if not SearchInDocument(eSearch.Text, ABackward) then
    ShowMessage('Text "' + eSearch.Text + '" not found.');
end;

procedure TMainF.bSearchClick(Sender: TObject);
begin
  RunSearch(False);
end;

procedure TMainF.bSearchPrevClick(Sender: TObject);
begin
  RunSearch(True);
end;

procedure TMainF.eSearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    RunSearch(ssShift in Shift);
  end;
end;

procedure TMainF.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Shift = [ssCtrl] then
  begin
    case Key of
      VK_LEFT: bPrevClick(Sender);
      VK_RIGHT: bNextClick(Sender);
      VK_ADD, VK_OEM_PLUS: bZoomInClick(Sender);
      VK_SUBTRACT, VK_OEM_MINUS: bZoomOutClick(Sender);
      VK_0: bZoomAutoClick(Sender);
    end;
  end
  else
  begin
    case Key of
      VK_F3:
        begin
          if Shift - [ssShift] = [] then
            RunSearch(ssShift in Shift);
        end;
      VK_PRIOR: bPrevClick(Sender);
      VK_NEXT: bNextClick(Sender);
      VK_HOME:
        begin
          PdfViewer1.GotoPage(0);
          sePageNo.Value := PdfViewer1.PageIndex + 1;
        end;
      VK_END:
        begin
          if PdfViewer1.Document = nil then
            exit;
          PdfViewer1.GotoPage(PdfViewer1.Document.PageCount - 1);
          sePageNo.Value := PdfViewer1.PageIndex + 1;
        end;
    end;
  end;
end;

procedure TMainF.bShowAttClick(Sender: TObject);
var
  Attachments: TPdfAttachmentList;
  buf: TBytes;
  ss: TStringStream;
begin
  if (lbAttachments.ItemIndex < 0) or (FPdfDoc = nil) then
    exit;
  Attachments := TPdfAttachmentList.Create(FPdfDoc);
  try
    if lbAttachments.ItemIndex >= Attachments.Count then
      exit;
    buf := Attachments[lbAttachments.ItemIndex].GetData;
  finally
    Attachments.Free;
  end;
  Application.CreateForm(TAttachmentF, AttachmentF);
  try
    ss := TStringStream.Create('');
    try
      if Length(buf) > 0 then
        ss.Write(buf[0], Length(buf));
      AttachmentF.mAttachment.Text := ss.DataString;
    finally
      ss.Free;
    end;
    AttachmentF.ShowModal;
  finally
    FreeAndNil(AttachmentF);
  end;
end;

procedure TMainF.bShowImgClick(Sender: TObject);
begin
  if (lbImages.ItemIndex < 0) or (FPdfDoc = nil) then
    exit;
  Application.CreateForm(TImageF, ImageF);
  ImageF.ImageIndex := lbImages.ItemIndex;
  ImageF.ShowModal;
  FreeAndNil(ImageF);
end;

procedure TMainF.chbUCSEnableChange(Sender: TObject);
begin
  PdfViewer1.UseColorScheme := chbUCSEnable.Checked;
  PdfThumbnailPanel1.UseColorScheme := chbUCSEnable.Checked;
end;

procedure TMainF.clbColorChanged(Sender: TObject);
var
  clb: TColorButton;
begin
  if not (Sender is TColorButton) then
    exit;
  clb := TColorButton(Sender);
  case LowerCase(clb.Name) of
    'clbbgcolor':
      begin
        PdfViewer1.BackgroundColor := clb.ButtonColor;
        PdfThumbnailPanel1.BackgroundColor := clb.ButtonColor;
      end;
    'clbtscolor': PdfViewer1.SelectionColor := clb.ButtonColor;
    'clbucsbg':
      begin
        PdfViewer1.SchemeBackgroundColor := clb.ButtonColor;
        PdfThumbnailPanel1.SchemeBackgroundColor := clb.ButtonColor;
      end;
    'clbucstf':
      begin
        PdfViewer1.SchemeTextFillColor := clb.ButtonColor;
        PdfThumbnailPanel1.SchemeTextFillColor := clb.ButtonColor;
      end;
    'clbucsts':
      begin
        PdfViewer1.SchemeTextStrokeColor := clb.ButtonColor;
        PdfThumbnailPanel1.SchemeTextStrokeColor := clb.ButtonColor;
      end;
    'clbucspf':
      begin
        PdfViewer1.SchemePathFillColor := clb.ButtonColor;
        PdfThumbnailPanel1.SchemePathFillColor := clb.ButtonColor;
      end;
    'clbucsps':
      begin
        PdfViewer1.SchemePathStrokeColor := clb.ButtonColor;
        PdfThumbnailPanel1.SchemePathStrokeColor := clb.ButtonColor;
      end;
  end;
end;

procedure TMainF.chbCenterChange(Sender: TObject);
begin
  PdfViewer1.CenterHorizontally := chbCenter.Checked;
  PdfViewer1.CenterVertically := chbCenter.Checked;
end;

procedure TMainF.chbShowThumbChange(Sender: TObject);
begin
  tsThumbnails.TabVisible := chbShowThumb.Checked;
  if chbShowThumb.Checked and (FPdfDoc <> nil) then
    PdfThumbnailPanel1.Document := FPdfDoc
  else
    PdfThumbnailPanel1.Document := nil;
end;

procedure TMainF.cbZoomModeChange(Sender: TObject);
begin
  if PdfViewer1.ZoomMode <> zmManual then
    AutoZoomPage;
end;

procedure TMainF.bNextClick(Sender: TObject);
begin
  PdfViewer1.GotoPage(PdfViewer1.PageIndex + 1);
  sePageNo.Value := PdfViewer1.PageIndex + 1;
end;

procedure TMainF.bCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TMainF.bGetTextClick(Sender: TObject);
begin
  Application.CreateForm(TTextF, TextF);
  TextF.ShowModal;
  FreeAndNil(TextF);
end;

procedure TMainF.bOpenClick(Sender: TObject);
var
  pwd: String;
begin
  if not odPDF.Execute then
    exit;
  if FPdfDoc <> nil then
  begin
    ResetSearch;
    tvBookmarks.Items.Clear;
    FreeAndNil(FBookmarks);
    PdfViewer1.Document := nil;
    PdfThumbnailPanel1.Document := nil;
    FreeAndNil(FPdfDoc);
  end;
  try
    FPdfDoc := TPdfDocument.Create();
    FPdfDoc.LoadFromFile(odPDF.FileName);
  except
    on E: EPdfiumError do
    begin
      if E.ErrorCode = FPDF_ERR_PASSWORD then
      begin
        if InputQuery('PDF', 'Enter password:', True, pwd) then
        begin
          try
            FPdfDoc.LoadFromFile(odPDF.FileName, pwd);
          except
            on E: EPdfiumError do
            begin
              FreeAndNil(FPdfDoc);
              ShowMessage('Could not open "' + odPDF.FileName + '": ' + E.Message);
              exit;
            end;
          end;
        end;
      end
      else
      begin
        FreeAndNil(FPdfDoc);
        ShowMessage('Could not open "' + odPDF.FileName + '": ' + E.Message);
        exit;
      end;
    end;
  end;
  Caption := 'Pdfium4Laz Viewer - ' + odPDF.FileName;
  PdfViewer1.Document := FPdfDoc;
  AutoZoomPage;
  LoadBookmarks;
  if chbShowThumb.Checked then
    PdfThumbnailPanel1.Document := FPdfDoc;
  LoadImages;
  LoadAttachments;
  sePageNo.Enabled := FPdfDoc.PageCount > 1;
  bPrev.Enabled := FPdfDoc.PageCount > 1;
  bNext.Enabled := FPdfDoc.PageCount > 1;
  ePageCount.Text := '/ ' + IntToStr(FPdfDoc.PageCount);
  PdfViewer1.SetFocus;
end;

procedure TMainF.sePageNoChange(Sender: TObject);
begin
  if sePageNo.Value <= PdfViewer1.Document.PageCount then
    PdfViewer1.PageIndex := sePageNo.Value - 1
  else
    sePageNo.Value := PdfViewer1.Document.PageCount;
end;

procedure TMainF.seTSAlphaChange(Sender: TObject);
begin
  PdfViewer1.SelectionAlpha := seTSAlpha.Value;
end;

const
  BookmarkPageColor = TColor($404040);

function TMainF.BookmarkOfNode(ANode: TTreeNode): TPdfBookmark;
begin
  Result := nil;
  if ANode <> nil then
    Result := TPdfBookmark(ANode.Data);
end;

procedure TMainF.tvBookmarksSelectionChanged(Sender: TObject);
var
  bm: TPdfBookmark;
begin
  if FBookmarkSyncing then
    exit;
  bm := BookmarkOfNode(tvBookmarks.Selected);
  if bm <> nil then
    PdfViewer1.GotoBookmark(bm);
end;

procedure TMainF.SyncBookmarkToPage(APageIndex: Integer);
var
  node: TTreeNode;
  bm: TPdfBookmark;
begin
  bm := BookmarkOfNode(tvBookmarks.Selected);
  if (bm <> nil) and (bm.PageIndex = APageIndex) then
    exit;
  node := tvBookmarks.Items.GetFirstNode;
  while node <> nil do
  begin
    bm := BookmarkOfNode(node);
    if (bm <> nil) and (bm.PageIndex = APageIndex) then
      break;
    node := node.GetNext;
  end;
  FBookmarkSyncing := True;
  try
    tvBookmarks.Selected := node;
    if node <> nil then
      node.MakeVisible;
  finally
    FBookmarkSyncing := False;
  end;
end;

procedure TMainF.tvBookmarksAdvancedCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode;
  State: TCustomDrawState; Stage: TCustomDrawStage; var PaintImages, DefaultDraw: Boolean);
var
  bm: TPdfBookmark;
  r: TRect;
  s: String;
begin
  if Stage <> cdPostPaint then
    exit;
  bm := BookmarkOfNode(Node);
  if (bm = nil) or (bm.PageIndex < 0) then
    exit;
  s := IntToStr(bm.PageIndex + 1);
  r := Node.DisplayRect(False);
  r.Left := r.Right - FBookmarkPageWidth;
  with Sender.Canvas do
  begin
    if Node.Selected then
    begin
      Brush.Color := Sender.SelectionColor;
      Font.Color := Sender.SelectionFontColor;
    end
    else
    begin
      Brush.Color := Sender.BackgroundColor;
      Font.Color := BookmarkPageColor;
    end;
    FillRect(r);
    Brush.Style := bsClear;
    TextOut(r.Right - TextWidth(s) - Scale96ToFont(4), r.Top + (r.Height - TextHeight(s)) div 2, s);
  end;
end;

{$IFDEF DEBUG}
procedure TMainF.LogException(Sender: TObject; E: Exception);
var
  fn: String;
  tf: TextFile;
  i: Integer;
  frames: PPointer;
begin
  fn := Application.Location + 'crash.log';
  frames := ExceptFrames;
  AssignFile(tf, fn);
  if not FileExists(fn) then
    Rewrite(tf)
  else
    Append(tf);
  try
    WriteLn(tf, FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' Exception: ' + E.ClassName + ': ' + E.Message);
    WriteLn(tf, 'Address: ' + BackTraceStrFunc(ExceptAddr));
    for i := 0 to ExceptFrameCount - 1 do
      WriteLn(tf, '  ' + BackTraceStrFunc(frames[i]));
  finally
    CloseFile(tf);
  end;
  Application.ShowException(E);
end;
{$ENDIF}

procedure TMainF.AutoZoomPage;
begin
  case cbZoomMode.ItemIndex of
    1: PdfViewer1.ZoomToFitWidth;
    2: PdfViewer1.ZoomToFitHeight;
    else
      PdfViewer1.ZoomToFitPage;
  end;
end;

function TMainF.SearchInDocument(AText: String; ABackward: Boolean = False): Boolean;
var
  match: TPdfSearchMatch;
  flags: TPdfSearchFlags;
  pass, pageCount, startIndex: Integer;
  found: Boolean;
begin
  Result := False;
  if (FPdfDoc = nil) or (FPdfDoc.PageCount = 0) or (AText = '') then
    exit;
  flags := [];
  if chbMatchCase.Checked then
    Include(flags, sfMatchCase);
  if (AText <> FLastSearchedText) or (flags <> FSearchFlags) or (PdfViewer1.PageIndex <> FSearchPageIndex) then
  begin
    ResetSearch;
    FLastSearchedText := AText;
    FSearchFlags := flags;
    FSearchPageIndex := PdfViewer1.PageIndex;
  end;
  pageCount := FPdfDoc.PageCount;
  for pass := 0 to pageCount do
  begin
    if FSearchInstance = nil then
    begin
      if ABackward then
        startIndex := -1
      else
        startIndex := 0;
      FSearchTextPage := TPdfTextPage.Create(FPdfDoc.Pages[FSearchPageIndex]);
      FSearchInstance := TPdfSearch.Create(FSearchTextPage, FLastSearchedText, FSearchFlags, startIndex);
    end;
    if ABackward then
      found := FSearchInstance.FindPrev(match)
    else
      found := FSearchInstance.FindNext(match);
    if found then
    begin
      PdfViewer1.GotoPage(FSearchPageIndex);
      sePageNo.Value := FSearchPageIndex + 1;
      PdfViewer1.SelectTextRange(match.StartIndex, match.Count);
      Result := True;
      exit;
    end;
    FreeAndNil(FSearchInstance);
    FreeAndNil(FSearchTextPage);
    if ABackward then
      FSearchPageIndex := (FSearchPageIndex + pageCount - 1) mod pageCount
    else
      FSearchPageIndex := (FSearchPageIndex + 1) mod pageCount;
  end;
end;

procedure TMainF.ResetSearch;
begin
  FreeAndNil(FSearchInstance);
  FreeAndNil(FSearchTextPage);
  FLastSearchedText := '';
  FSearchPageIndex := 0;
  FSearchFlags := [];
end;

procedure TMainF.LoadBookmarks;
var
  maxPage: Integer;
  root: TPdfBookmark;

  procedure AddNodes(AParentNode: TTreeNode; ABookmark: TPdfBookmark);
  var
    child: TPdfBookmark;
  begin
    if ABookmark.PageIndex > maxPage then
      maxPage := ABookmark.PageIndex;
    AParentNode := tvBookmarks.Items.AddChildObject(AParentNode, ABookmark.Title, ABookmark);
    for child in ABookmark do
      AddNodes(AParentNode, child);
  end;

begin
  tvBookmarks.Items.BeginUpdate;
  try
    tvBookmarks.Items.Clear;
    FreeAndNil(FBookmarks);
    if FPdfDoc = nil then
      exit;
    FBookmarks := TPdfBookmarkTree.Create(FPdfDoc);
    maxPage := 0;
    for root in FBookmarks do
      AddNodes(nil, root);
    Canvas.Font.Assign(tvBookmarks.Font);
    FBookmarkPageWidth := Canvas.TextWidth(IntToStr(maxPage + 1)) + Scale96ToFont(12);
    if tvBookmarks.Items.Count > 0 then
      tvBookmarks.Items.GetFirstNode.Expanded := True;
  finally
    tvBookmarks.Items.EndUpdate;
  end;
  SyncBookmarkToPage(PdfViewer1.PageIndex);
end;

procedure TMainF.LoadImages;
var
  Images: TPdfImageList;
  i: Integer;
begin
  lbImages.Items.Clear;
  if FPdfDoc = nil then
    exit;
  Images := TPdfImageList.CreateForDocument(FPdfDoc);
  lbImages.Items.BeginUpdate;
  for i := 0 to Images.Count - 1 do
    lbImages.Items.AddObject(Format('Image %d - page %d (%d x %d px)', [i + 1, Images[i].PageIndex + 1,
      Images[i].PixelWidth, Images[i].PixelHeight]), TObject(PtrInt(i)));
  Images.Free;
  lbImages.Items.EndUpdate;
  bShowImg.Enabled := lbImages.Items.Count > 0;
  bSaveImg.Enabled := lbImages.Items.Count > 0;
end;

procedure TMainF.LoadAttachments;
var
  Attachments: TPdfAttachmentList;
  i: Integer;
begin
  lbAttachments.Items.Clear;
  if FPdfDoc = nil then
    exit;
  Attachments := TPdfAttachmentList.Create(FPdfDoc);
  lbAttachments.Items.BeginUpdate;
  for i := 0 to Attachments.Count - 1 do
    lbAttachments.Items.AddObject(Format('%s (%f kb)', [Attachments[i].Name, Attachments[i].Size / 1024]), TObject(PtrInt(i)));
  Attachments.Free;
  lbAttachments.Items.EndUpdate;
  bShowAtt.Enabled := lbAttachments.Items.Count > 0;
  bSaveAtt.Enabled := lbAttachments.Items.Count > 0;
end;

end.

