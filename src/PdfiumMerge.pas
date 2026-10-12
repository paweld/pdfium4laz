unit PdfiumMerge;

{$mode objfpc}{$H+}{$inline on}

interface

uses
  Classes, SysUtils, base64, PdfiumLib, PdfiumCore;

procedure PdfMergeStreams(const ASources: array of TStream; ADest: TStream);
procedure PdfMergeFiles(const ASourceFiles: array of String; const AOutputFile: String);

procedure PdfSplitToStream(ASource: TStream; const APages: array of Integer; ADest: TStream); overload;
procedure PdfSplitToStream(ASource: TStream; AFirstPage, ALastPage: Integer; ADest: TStream); overload;

procedure PdfSplitPages(const ASourceFile: String; const AOutputDir: String; const APages: array of Integer); overload;
procedure PdfSplitRange(const ASourceFile: String; const AOutputFile: String; AFirstPage, ALastPage: Integer); overload;

implementation

const
  { Minimal blank-page PDF used as a "shell" document for split operations.
    KNOWN BUG worked around here: FPDF_CreateNewDocument's handle crashes on
    every subsequent call in this PDFium build. }
  BLANK_PDF_TEMPLATE_BASE64 =
    'JVBERi0xLjMKJenr8b8KMSAwIG9iago8PAovQ291bnQgMQovS2lkcyBbMyAwIFJdCi9NZWRpYUJv' +
    'eCBbMCAwIDU5NS4yOCA4NDEuODldCi9UeXBlIC9QYWdlcwo+PgplbmRvYmoKMiAwIG9iago8PAov' +
    'T3BlbkFjdGlvbiBbMyAwIFIgL0ZpdEggbnVsbF0KL1BhZ2VMYXlvdXQgL09uZUNvbHVtbgovUGFn' +
    'ZXMgMSAwIFIKL1R5cGUgL0NhdGFsb2cKPj4KZW5kb2JqCjMgMCBvYmoKPDwKL0NvbnRlbnRzIDQg' +
    'MCBSCi9QYXJlbnQgMSAwIFIKL1Jlc291cmNlcyA1IDAgUgovVHlwZSAvUGFnZQo+PgplbmRvYmoK' +
    'NCAwIG9iago8PAovRmlsdGVyIC9GbGF0ZURlY29kZQovTGVuZ3RoIDE5Cj4+CnN0cmVhbQp4nDNS' +
    '8OIy0DM1VyjnAgAL/AISCmVuZHN0cmVhbQplbmRvYmoKNSAwIG9iago8PAovUHJvY1NldCBbL1BE' +
    'RiAvVGV4dCAvSW1hZ2VCIC9JbWFnZUMgL0ltYWdlSV0KPj4KZW5kb2JqCjYgMCBvYmoKPDwKL0Ny' +
    'ZWF0aW9uRGF0ZSAoRDoyMDI2MDkwNTA2NTE1N1opCj4+CmVuZG9iagp4cmVmCjAgNwowMDAwMDAw' +
    'MDAwIDY1NTM1IGYgCjAwMDAwMDAwMTUgMDAwMDAgbiAKMDAwMDAwMDEwMiAwMDAwMCBuIAowMDAw' +
    'MDAwMjA1IDAwMDAwIG4gCjAwMDAwMDAyODUgMDAwMDAgbiAKMDAwMDAwMDM3NSAwMDAwMCBuIAow' +
    'MDAwMDAwNDQyIDAwMDAwIG4gCnRyYWlsZXIKPDwKL1NpemUgNwovUm9vdCAyIDAgUgovSW5mbyA2' +
    'IDAgUgovSUQgWzxENkRFN0Y4NDNDNzk1QjVEQUZBNTRBNzhFNkJFNTJDNT48RDZERTdGODQzQzc5' +
    'NUI1REFGQTU0QTc4RTZCRTUyQzU+XQo+PgpzdGFydHhyZWYKNDk3CiUlRU9GCg==';

var
  gBlankTemplateBytes: String;

procedure EnsureBlankTemplateLoaded;
begin
  if gBlankTemplateBytes = '' then
    gBlankTemplateBytes := DecodeStringBase64(BLANK_PDF_TEMPLATE_BASE64);
end;

function CreateShellDocument: FPDF_DOCUMENT;
begin
  EnsureBlankTemplateLoaded;
  PdfiumGlobalLock.Enter;
  try
    Result := FPDF_LoadMemDocument64(@gBlankTemplateBytes[1], Length(gBlankTemplateBytes), nil);
  finally
    PdfiumGlobalLock.Leave;
  end;
  if Result = nil then
    raise EPdfiumError.Create('Could not load the internal blank document template.');
end;

type
  TStreamFileWrite = record
    Base: FPDF_FILEWRITE;
    Stream: TStream;
  end;
  PStreamFileWrite = ^TStreamFileWrite;

function StreamWriteBlockCallback(AThis: PFPDF_FILEWRITE; AData: Pointer; ASize: FPDF_ULONG): Integer; cdecl;
begin
  PStreamFileWrite(AThis)^.Stream.WriteBuffer(AData^, ASize);
  Result := 1;
end;

procedure SaveDocumentToStream(ADocHandle: FPDF_DOCUMENT; ADest: TStream);
var
  sfw: TStreamFileWrite;
  ok: FPDF_BOOL;
begin
  sfw.Base.version := 1;
  sfw.Base.WriteBlock := @StreamWriteBlockCallback;
  sfw.Stream := ADest;
  PdfiumGlobalLock.Enter;
  try
    ok := FPDF_SaveAsCopy(ADocHandle, @sfw.Base, 0);
  finally
    PdfiumGlobalLock.Leave;
  end;
  if ok = 0 then
    raise EPdfiumError.Create('Could not save the resulting document.');
end;

procedure PdfMergeStreams(const ASources: array of TStream; ADest: TStream);
var
  destDoc: TPdfDocument;
  srcDoc: TPdfDocument;
  i, insertAt: Integer;
  imported: FPDF_BOOL;
begin
  PdfiumEnsureInitialized;
  if Length(ASources) = 0 then
    raise EPdfiumError.Create('PdfMergeStreams: ASources must not be empty.');
  { The first source doubles as the growing destination document - it already
    is a real loaded FPDF_DOCUMENT, sidestepping FPDF_CreateNewDocument. }
  destDoc := TPdfDocument.Create;
  try
    destDoc.LoadFromStream(ASources[0]);
    insertAt := destDoc.PageCount;
    for i := 1 to High(ASources) do
    begin
      srcDoc := TPdfDocument.Create;
      try
        srcDoc.LoadFromStream(ASources[i]);
        PdfiumGlobalLock.Enter;
        try
          imported := FPDF_ImportPages(destDoc.Handle, srcDoc.Handle, nil, insertAt);
        finally
          PdfiumGlobalLock.Leave;
        end;
        if imported = 0 then
          raise EPdfiumError.Create(Format('PdfMergeStreams: failed to import pages from source %d.', [i]));
        Inc(insertAt, srcDoc.PageCount);
      finally
        srcDoc.Free;
      end;
    end;
    SaveDocumentToStream(destDoc.Handle, ADest);
  finally
    destDoc.Free;
  end;
end;

procedure PdfMergeFiles(const ASourceFiles: array of String; const AOutputFile: String);
var
  streams: array of TStream;
  destStream: TFileStream;
  i: Integer;
begin
  if Length(ASourceFiles) = 0 then
    raise EPdfiumError.Create('PdfMergeFiles: ASourceFiles must not be empty.');
  SetLength(streams, Length(ASourceFiles));
  try
    for i := 0 to High(ASourceFiles) do
      streams[i] := TFileStream.Create(ASourceFiles[i], fmOpenRead or fmShareDenyWrite);
    destStream := TFileStream.Create(AOutputFile, fmCreate);
    try
      PdfMergeStreams(streams, destStream);
    finally
      destStream.Free;
    end;
  finally
    for i := 0 to High(streams) do
      streams[i].Free;
  end;
end;

procedure PdfSplitToStream(ASource: TStream; const APages: array of Integer; ADest: TStream);
var
  shellDoc: FPDF_DOCUMENT;
  srcDoc: TPdfDocument;
  indices: array of Integer;
  i: Integer;
  imported: FPDF_BOOL;
begin
  PdfiumEnsureInitialized;
  if Length(APages) = 0 then
    raise EPdfiumError.Create('PdfSplitToStream: APages must not be empty.');
  SetLength(indices, Length(APages));
  for i := 0 to High(APages) do
    indices[i] := APages[i];

  shellDoc := CreateShellDocument;
  try
    srcDoc := TPdfDocument.Create;
    try
      srcDoc.LoadFromStream(ASource);
      PdfiumGlobalLock.Enter;
      try
        imported := FPDF_ImportPagesByIndex(shellDoc, srcDoc.Handle, @indices[0], Length(indices), 0);
      finally
        PdfiumGlobalLock.Leave;
      end;
      if imported = 0 then
        raise EPdfiumError.Create('PdfSplitToStream: failed to import the requested pages.');
    finally
      srcDoc.Free;
    end;
    { The template's own placeholder page was pushed to the end by the import
      above; discard it before saving. }
    PdfiumGlobalLock.Enter;
    try
      FPDFPage_Delete(shellDoc, Length(indices));
    finally
      PdfiumGlobalLock.Leave;
    end;
    SaveDocumentToStream(shellDoc, ADest);
  finally
    PdfiumGlobalLock.Enter;
    try
      FPDF_CloseDocument(shellDoc);
    finally
      PdfiumGlobalLock.Leave;
    end;
  end;
end;

procedure PdfSplitToStream(ASource: TStream; AFirstPage, ALastPage: Integer; ADest: TStream);
var
  indices: array of Integer;
  i, n: Integer;
begin
  if ALastPage < AFirstPage then
    raise EPdfiumError.Create('PdfSplitToStream: ALastPage must not be less than AFirstPage.');
  n := ALastPage - AFirstPage + 1;
  SetLength(indices, n);
  for i := 0 to n - 1 do
    indices[i] := AFirstPage + i;
  PdfSplitToStream(ASource, indices, ADest);
end;

procedure PdfSplitPages(const ASourceFile: String; const AOutputDir: String; const APages: array of Integer);
var
  srcStream: TFileStream;
  destStream: TFileStream;
  i: Integer;
  outPath: String;
begin
  srcStream := TFileStream.Create(ASourceFile, fmOpenRead or fmShareDenyWrite);
  try
    for i := 0 to High(APages) do
    begin
      outPath := IncludeTrailingPathDelimiter(AOutputDir) + Format('page_%.4d.pdf', [APages[i] + 1]);
      destStream := TFileStream.Create(outPath, fmCreate);
      try
        srcStream.Position := 0;
        PdfSplitToStream(srcStream, [APages[i]], destStream);
      finally
        destStream.Free;
      end;
    end;
  finally
    srcStream.Free;
  end;
end;

procedure PdfSplitRange(const ASourceFile: String; const AOutputFile: String; AFirstPage, ALastPage: Integer);
var
  srcStream, destStream: TFileStream;
begin
  srcStream := TFileStream.Create(ASourceFile, fmOpenRead or fmShareDenyWrite);
  try
    destStream := TFileStream.Create(AOutputFile, fmCreate);
    try
      PdfSplitToStream(srcStream, AFirstPage, ALastPage, destStream);
    finally
      destStream.Free;
    end;
  finally
    srcStream.Free;
  end;
end;

end.
