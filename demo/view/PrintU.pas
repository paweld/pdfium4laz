unit PrintU;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Spin, Printers,
  PdfiumCore, PdfiumLib, PdfiumPrint;

type

  { TPrintF }

  TPrintF = class(TForm)
    bPrint: TButton;
    bCancel: TButton;
    bCurrentPage: TButton;
    cbPrinter: TComboBox;
    chbFitToPage: TCheckBox;
    ePages: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    lProgress: TLabel;
    seCopies: TSpinEdit;
    procedure bCancelClick(Sender: TObject);
    procedure bCurrentPageClick(Sender: TObject);
    procedure bPrintClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormShow(Sender: TObject);
  private
    FDocument: TPdfDocument;
    FCurrentPage: Integer;
    { Non-nil only while printing - freed by itself after DocumentPrinted. }
    FJob: TPdfPrintJob;
    procedure PagePrinted(Sender: TObject);
    procedure DocumentPrinted(Sender: TObject);
    procedure SetControlsEnabled(AEnabled: Boolean);
  public
    property Document: TPdfDocument read FDocument write FDocument;
    property CurrentPage: Integer read FCurrentPage write FCurrentPage;
  end;

var
  PrintF: TPrintF;

implementation

{$R *.lfm}

{ TPrintF }

procedure TPrintF.FormShow(Sender: TObject);
begin
  cbPrinter.Items.Assign(Printer.Printers);
  if cbPrinter.Items.Count = 0 then
  begin
    bPrint.Enabled := False;
    cbPrinter.Enabled := False;
    cbPrinter.Text := 'No printer installed';
    exit;
  end
  else
  begin
    if (Printer.PrinterIndex >= 0) and (Printer.PrinterIndex < cbPrinter.Items.Count) then
      cbPrinter.ItemIndex := Printer.PrinterIndex
    else
      cbPrinter.ItemIndex := 0;
    if FDocument <> nil then
      ePages.TextHint := Format('e.g. 1-3,5,8  (empty = all %d pages)', [FDocument.PageCount]);
  end;
end;

procedure TPrintF.bCurrentPageClick(Sender: TObject);
begin
  ePages.Text := IntToStr(FCurrentPage + 1);
end;

procedure TPrintF.bCancelClick(Sender: TObject);
begin
  if FJob <> nil then
  begin
    FJob.Cancel;
    lProgress.Caption := 'Cancelling...';
    bCancel.Enabled := False;
  end
  else
    ModalResult := mrCancel;
end;

procedure TPrintF.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  { The job calls back into this form - it has to finish first. }
  CanClose := FJob = nil;
  if not CanClose then
    bCancelClick(nil);
end;

procedure TPrintF.SetControlsEnabled(AEnabled: Boolean);
begin
  bPrint.Enabled := AEnabled;
  bCurrentPage.Enabled := AEnabled;
  cbPrinter.Enabled := AEnabled;
  seCopies.Enabled := AEnabled;
  ePages.Enabled := AEnabled;
  chbFitToPage.Enabled := AEnabled;
  bCancel.Enabled := True;
end;

procedure TPrintF.PagePrinted(Sender: TObject);
var
  job: TPdfPrintJob;
begin
  job := TPdfPrintJob(Sender);
  lProgress.Caption := Format('Printed page %d (%d of %d)', [job.PageIndex + 1, job.PrintedCount, job.PageCount]);
end;

procedure TPrintF.DocumentPrinted(Sender: TObject);
var
  job: TPdfPrintJob;
begin
  job := TPdfPrintJob(Sender);
  FJob := nil;
  SetControlsEnabled(True);
  if job.ErrorMessage <> '' then
  begin
    lProgress.Caption := '';
    ShowMessage('Could not print: ' + job.ErrorMessage);
  end
  else if job.Cancelled then
    lProgress.Caption := 'Printing cancelled.'
  else
    ModalResult := mrOk;
end;

procedure TPrintF.bPrintClick(Sender: TObject);
var
  opts: TPdfPrintOptions;
  spec: String;
begin
  if (FDocument = nil) or (cbPrinter.ItemIndex < 0) or (FJob <> nil) then
    exit;
  spec := Trim(ePages.Text);
  if spec = '' then
    spec := '*';
  opts := PdfDefaultPrintOptions;
  opts.PrinterName := cbPrinter.Items[cbPrinter.ItemIndex];
  opts.Copies := seCopies.Value;
  if chbFitToPage.Checked then
    opts.PageSize := ppsFitToPage
  else
    opts.PageSize := ppsShrinkToFit;
  try
    FJob := PdfPrintPagesAsync(FDocument, spec, opts, @PagePrinted, @DocumentPrinted);
  except
    on E: EPdfiumError do
    begin
      ShowMessage('Could not print: ' + E.Message);
      ePages.SetFocus;
      exit;
    end;
  end;
  SetControlsEnabled(False);
  lProgress.Caption := 'Printing...';
end;

end.
