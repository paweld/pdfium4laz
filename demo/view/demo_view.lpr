program pdfium4laz_demo;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$IFDEF HASAMIGA}
  athreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, printer4lazarus, MainU;

{$R *.res}

begin
  {$IFDEF DEBUG}SetHeapTraceOutput('heaptrace.log');{$ENDIF}
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TMainF, MainF);
  Application.Run;
end.

