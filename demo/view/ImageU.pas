unit ImageU;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls, LCLType,
  PdfiumImages;

type

  { TImageF }

  TImageF = class(TForm)
    bClose: TButton;
    bPrevImg: TButton;
    bNextImg: TButton;
    Image1: TImage;
    Label1: TLabel;
    Panel1: TPanel;
    procedure bCloseClick(Sender: TObject);
    procedure bNextImgClick(Sender: TObject);
    procedure bPrevImgClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormShow(Sender: TObject);
  private
    procedure ShowImage(AValue: Integer = 0);
  public
    ImageIndex: Integer;
  end;

var
  ImageF: TImageF;

implementation

{$R *.lfm}

{ TImageF }

uses
  MainU;

var
  FImages: TPdfImageList;

procedure TImageF.bCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TImageF.bNextImgClick(Sender: TObject);
begin
  ShowImage(1);
end;

procedure TImageF.bPrevImgClick(Sender: TObject);
begin
  ShowImage(-1);
end;

procedure TImageF.FormCreate(Sender: TObject);
begin
  ImageIndex := -1;
  FImages := TPdfImageList.CreateForDocument(MainF.PdfDoc);
end;

procedure TImageF.FormDestroy(Sender: TObject);
begin
  FImages.Free;
end;

procedure TImageF.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_ESCAPE: Close;
    VK_BACK, VK_LEFT: ShowImage(-1);
    VK_SPACE, VK_RIGHT: ShowImage(1);
  end;
end;

procedure TImageF.FormShow(Sender: TObject);
begin
  ShowImage;
end;

procedure TImageF.ShowImage(AValue: Integer);
var
  ms: TMemoryStream;
begin
  if (ImageIndex < 0) or (FImages.Count = 0) or (MainF.PdfDoc = nil) then
    exit;
  ImageIndex := ImageIndex + AValue;
  if ImageIndex >= FImages.Count then
    ImageIndex := 0
  else if ImageIndex < 0 then
    ImageIndex := FImages.Count - 1;
  ms := TMemoryStream.Create;
  FImages[ImageIndex].SaveToStream(ms);
  Label1.Caption := Format('Image %d - page %d (%d x %d px)', [ImageIndex + 1, FImages[ImageIndex].PageIndex + 1,
      FImages[ImageIndex].PixelWidth, FImages[ImageIndex].PixelHeight]);
  ms.Position := 0;
  Image1.Picture.LoadFromStream(ms);
  ms.Free;
end;

end.

