unit AttachmentU;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, LCLType, StdCtrls;

type

  { TAttachmentF }

  TAttachmentF = class(TForm)
    bClose: TButton;
    mAttachment: TMemo;
    Panel1: TPanel;
    procedure bCloseClick(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private

  public

  end;

var
  AttachmentF: TAttachmentF;

implementation

{$R *.lfm}

{ TAttachmentF }

procedure TAttachmentF.bCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TAttachmentF.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
    Close;
end;

end.

