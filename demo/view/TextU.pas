unit TextU;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, LCLType,
  PdfiumText;

type

  { TTextF }

  TTextF = class(TForm)
    bClose: TButton;
    mPageText: TMemo;
    rgTextFormat: TRadioGroup;
    procedure bCloseClick(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormShow(Sender: TObject);
    procedure rgTextFormatClick(Sender: TObject);
  private

  public

  end;

var
  TextF: TTextF;

implementation

{$R *.lfm}

{ TTextF }

uses
  MainU;

procedure TTextF.bCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TTextF.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_ESCAPE: Close;
    VK_P: rgTextFormat.ItemIndex := 0;
    VK_N: rgTextFormat.ItemIndex := 1;
    VK_F: rgTextFormat.ItemIndex := 2;
  end;
end;

procedure TTextF.FormShow(Sender: TObject);
begin
  rgTextFormatClick(Sender);
end;

procedure TTextF.rgTextFormatClick(Sender: TObject);
begin
  mPageText.Lines.Text := PdfGetText(MainF.PdfDoc.Pages[MainF.PdfViewer1.PageIndex], TPdfTextFormat(rgTextFormat.ItemIndex));
end;

end.

