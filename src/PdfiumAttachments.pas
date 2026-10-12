unit PdfiumAttachments;

{$mode objfpc}{$H+}{$inline on}

interface

uses
  Classes, SysUtils, SyncObjs, PdfiumLib, PdfiumCore;

const
  { PDFium has no key-enumeration call - this is the complete set HasKey/
    GetValueType/GetStringValue/SetStringValue can reach. SUBTYPE is listed
    for reference only - it is NOT actually reachable this way, see Subtype. }
  PDF_ATTACHMENT_KEY_DESC = 'Desc';
  PDF_ATTACHMENT_KEY_SUBTYPE = 'Subtype';
  PDF_ATTACHMENT_KEY_SIZE = 'Size';
  PDF_ATTACHMENT_KEY_CREATIONDATE = 'CreationDate';
  PDF_ATTACHMENT_KEY_MODDATE = 'ModDate';
  PDF_ATTACHMENT_KEY_CHECKSUM = 'CheckSum';

type
  TPdfAttachmentValueType = (avUnknown, avBoolean, avNumber, avString, avName, avArray, avDictionary, avStream, avNullObj, avReference);

  TPdfAttachmentItem = class
  private
    FDocHandle: FPDF_DOCUMENT;
    FHandle: FPDF_ATTACHMENT;
    { Borrowed from the owning TPdfAttachmentList's Document.Lock - not owned/freed here. }
    FLock: TCriticalSection;
    constructor Create(ADocHandle: FPDF_DOCUMENT; AHandle: FPDF_ATTACHMENT; ALock: TCriticalSection);
  public
    function Name: String;
    function Description: String;
    { MIME type (/Subtype). Read-only: PDFium has no API to set it. }
    function Subtype: String; // from pdfium/~7250
    { Raw PDF date string (e.g. "D:20260910123456+02'00'"), '' if not set. Not parsed into a TDateTime. }
    function CreationDate: String;
    function ModDate: String;
    { Hex MD5 digest as recorded by whatever tool produced the PDF - not verified against GetData. }
    function CheckSum: String;
    { PDFium has no key-enumeration call - only the PDF_ATTACHMENT_KEY_* constants above can be looked up. }
    function HasKey(const AKey: String): Boolean;
    function GetValueType(const AKey: String): TPdfAttachmentValueType;
    { '' if AKey does not exist or its value is not a string (e.g. SIZE, a number - use Size instead). }
    function GetStringValue(const AKey: String): String;
    { Does NOT reach PDF_ATTACHMENT_KEY_SUBTYPE - the call will not raise, but
      the value is not visible as the MIME type afterward. }
    procedure SetStringValue(const AKey, AValue: String);
    procedure SetDescription(const AValue: String);
    procedure SetData(const AData: TBytes);
    function Size: Int64;
    procedure SaveToStream(ADest: TStream);
    procedure SaveToFile(const AOutputPath: String);
    function GetData: TBytes;
  end;

  TPdfAttachmentList = class
  private
    FDocument: TPdfDocument;
    FItems: array of TPdfAttachmentItem;
    function GetItem(AIndex: Integer): TPdfAttachmentItem;
  public type
    TEnumerator = specialize TPdfEnumerator<TPdfAttachmentItem>;
  public
    function GetEnumerator: TEnumerator;
    constructor Create(ADocument: TPdfDocument);
    destructor Destroy; override;
    function Count: Integer;
    function FindByName(const AName: String): TPdfAttachmentItem;
    { Raises EPdfiumError if AName is empty or already used - PDFium itself
      silently refuses to add a duplicate, so this checks proactively. }
    function Add(const AName: String): TPdfAttachmentItem;
    { Only removes the entry from the name tree (PDFium's own documented
      behavior) - the underlying bytes only shrink on the next save. }
    procedure Delete(AIndex: Integer);
    property Document: TPdfDocument read FDocument;
    property Items[AIndex: Integer]: TPdfAttachmentItem read GetItem; default;
  end;

implementation

{ TPdfAttachmentItem }

constructor TPdfAttachmentItem.Create(ADocHandle: FPDF_DOCUMENT; AHandle: FPDF_ATTACHMENT; ALock: TCriticalSection);
begin
  inherited Create;
  FDocHandle := ADocHandle;
  FHandle := AHandle;
  FLock := ALock;
end;

function TPdfAttachmentItem.Name: String;
var
  neededBytes: LongWord;
  buffer: array of WideChar;
begin
  Result := '';
  FLock.Enter;
  try
    neededBytes := FPDFAttachment_GetName(FHandle, nil, 0);
    if neededBytes <= 2 then
      exit;
    SetLength(buffer, neededBytes div 2);
    FPDFAttachment_GetName(FHandle, @buffer[0], neededBytes);
    Result := PWideChar(@buffer[0]);
  finally
    FLock.Leave;
  end;
end;

function TPdfAttachmentItem.GetStringValue(const AKey: String): String;
var
  key: UTF8String;
  neededBytes: LongWord;
  buffer: array of WideChar;
begin
  Result := '';
  key := UTF8String(AKey);
  FLock.Enter;
  try
    neededBytes := FPDFAttachment_GetStringValue(FHandle, PAnsiChar(key), nil, 0);
    if neededBytes <= 2 then
      exit;
    SetLength(buffer, neededBytes div 2);
    FPDFAttachment_GetStringValue(FHandle, PAnsiChar(key), @buffer[0], neededBytes);
    Result := PWideChar(@buffer[0]);
  finally
    FLock.Leave;
  end;
end;

function TPdfAttachmentItem.Description: String;
begin
  Result := GetStringValue(PDF_ATTACHMENT_KEY_DESC);
end;

function TPdfAttachmentItem.Subtype: String;
var
  neededBytes: LongWord;
  buffer: array of WideChar;
begin
  Result := '';
  if not Assigned(FPDFAttachment_GetSubtype) then
    exit;
  FLock.Enter;
  try
    neededBytes := FPDFAttachment_GetSubtype(FHandle, nil, 0);
    if neededBytes <= 2 then
      exit;
    SetLength(buffer, neededBytes div 2);
    FPDFAttachment_GetSubtype(FHandle, @buffer[0], neededBytes);
    Result := PWideChar(@buffer[0]);
  finally
    FLock.Leave;
  end;
end;

function TPdfAttachmentItem.CreationDate: String;
begin
  Result := GetStringValue(PDF_ATTACHMENT_KEY_CREATIONDATE);
end;

function TPdfAttachmentItem.ModDate: String;
begin
  Result := GetStringValue(PDF_ATTACHMENT_KEY_MODDATE);
end;

function TPdfAttachmentItem.CheckSum: String;
begin
  Result := GetStringValue(PDF_ATTACHMENT_KEY_CHECKSUM);
end;

function TPdfAttachmentItem.HasKey(const AKey: String): Boolean;
begin
  FLock.Enter;
  try
    Result := FPDFAttachment_HasKey(FHandle, PAnsiChar(UTF8String(AKey))) <> 0;
  finally
    FLock.Leave;
  end;
end;

function TPdfAttachmentItem.GetValueType(const AKey: String): TPdfAttachmentValueType;
var
  raw: Integer;
begin
  FLock.Enter;
  try
    raw := FPDFAttachment_GetValueType(FHandle, PAnsiChar(UTF8String(AKey)));
  finally
    FLock.Leave;
  end;
  case raw of
    FPDF_OBJECT_BOOLEAN: Result := avBoolean;
    FPDF_OBJECT_NUMBER: Result := avNumber;
    FPDF_OBJECT_STRING: Result := avString;
    FPDF_OBJECT_NAME: Result := avName;
    FPDF_OBJECT_ARRAY: Result := avArray;
    FPDF_OBJECT_DICTIONARY: Result := avDictionary;
    FPDF_OBJECT_STREAM: Result := avStream;
    FPDF_OBJECT_NULLOBJ: Result := avNullObj;
    FPDF_OBJECT_REFERENCE: Result := avReference;
  else
    Result := avUnknown;
  end;
end;

procedure TPdfAttachmentItem.SetStringValue(const AKey, AValue: String);
var
  key: UTF8String;
begin
  key := UTF8String(AKey);
  FLock.Enter;
  try
    if FPDFAttachment_SetStringValue(FHandle, PAnsiChar(key), PWideChar(UnicodeString(AValue))) = 0 then
      raise EPdfiumError.Create(Format('Could not set attachment "%s" key "%s".', [Name, AKey]));
  finally
    FLock.Leave;
  end;
end;

{ KNOWN BUG worked around: the dedicated FPDFAttachment_SetDescription is a
  silent no-op in this PDFium build, so this goes through the generic
  SetStringValue instead. }
procedure TPdfAttachmentItem.SetDescription(const AValue: String);
begin
  SetStringValue(PDF_ATTACHMENT_KEY_DESC, AValue);
end;

procedure TPdfAttachmentItem.SetData(const AData: TBytes);
var
  contents: Pointer;
begin
  if Length(AData) = 0 then
    contents := nil
  else
    contents := @AData[0];
  FLock.Enter;
  try
    if FPDFAttachment_SetFile(FHandle, FDocHandle, contents, Length(AData)) = 0 then
      raise EPdfiumError.Create(Format('Could not set the data of attachment "%s".', [Name]));
  finally
    FLock.Leave;
  end;
end;

function TPdfAttachmentItem.GetData: TBytes;
var
  neededSize: FPDF_ULONG;
begin
  SetLength(Result, 0);
  neededSize := 0;
  FLock.Enter;
  try
    if FPDFAttachment_GetFile(FHandle, nil, 0, neededSize) = 0 then
      raise EPdfiumError.Create(Format('Could not read attachment "%s": the payload is not decodable.', [Name]));
    if neededSize = 0 then
      exit;
    SetLength(Result, neededSize);
    if FPDFAttachment_GetFile(FHandle, @Result[0], neededSize, neededSize) = 0 then
      raise EPdfiumError.Create(Format('Could not read attachment "%s" payload.', [Name]));
  finally
    FLock.Leave;
  end;
end;

function TPdfAttachmentItem.Size: Int64;
begin
  Result := Length(GetData);
end;

procedure TPdfAttachmentItem.SaveToStream(ADest: TStream);
var
  data: TBytes;
begin
  data := GetData;
  if Length(data) > 0 then
    ADest.WriteBuffer(data[0], Length(data));
end;

procedure TPdfAttachmentItem.SaveToFile(const AOutputPath: String);
var
  stream: TFileStream;
begin
  stream := TFileStream.Create(AOutputPath, fmCreate);
  try
    SaveToStream(stream);
  finally
    stream.Free;
  end;
end;

{ TPdfAttachmentList }

constructor TPdfAttachmentList.Create(ADocument: TPdfDocument);
var
  i, n: Integer;
  itemHandle: FPDF_ATTACHMENT;
begin
  inherited Create;
  FDocument := ADocument;
  FDocument.Lock.Enter;
  try
    n := FPDFDoc_GetAttachmentCount(ADocument.Handle);
    SetLength(FItems, n);
    for i := 0 to n - 1 do
    begin
      itemHandle := FPDFDoc_GetAttachment(ADocument.Handle, i);
      FItems[i] := TPdfAttachmentItem.Create(ADocument.Handle, itemHandle, ADocument.Lock);
    end;
  finally
    FDocument.Lock.Leave;
  end;
end;

destructor TPdfAttachmentList.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FItems) do
    FItems[i].Free;
  inherited Destroy;
end;

function TPdfAttachmentList.Count: Integer;
begin
  Result := Length(FItems);
end;

function TPdfAttachmentList.GetEnumerator: TEnumerator;
begin
  Result := TEnumerator.Create(@GetItem, Count);
end;

function TPdfAttachmentList.GetItem(AIndex: Integer): TPdfAttachmentItem;
begin
  if (AIndex < 0) or (AIndex >= Length(FItems)) then
    raise EPdfiumError.Create(Format('TPdfAttachmentList[]: attachment index %d is out of range (0..%d).', [AIndex, Length(FItems) - 1]));
  Result := FItems[AIndex];
end;

function TPdfAttachmentList.FindByName(const AName: String): TPdfAttachmentItem;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to High(FItems) do
  begin
    if FItems[i].Name = AName then
    begin
      Result := FItems[i];
      exit;
    end;
  end;
end;

function TPdfAttachmentList.Add(const AName: String): TPdfAttachmentItem;
var
  itemHandle: FPDF_ATTACHMENT;
begin
  if AName = '' then
    raise EPdfiumError.Create('Add: AName must not be empty.');
  if FindByName(AName) <> nil then
    raise EPdfiumError.Create(Format('Add: an attachment named "%s" already exists.', [AName]));
  FDocument.Lock.Enter;
  try
    itemHandle := FPDFDoc_AddAttachment(FDocument.Handle, PWideChar(UnicodeString(AName)));
  finally
    FDocument.Lock.Leave;
  end;
  if itemHandle = nil then
    raise EPdfiumError.Create(Format('Add: could not add attachment "%s".', [AName]));
  Result := TPdfAttachmentItem.Create(FDocument.Handle, itemHandle, FDocument.Lock);
  SetLength(FItems, Length(FItems) + 1);
  FItems[High(FItems)] := Result;
end;

procedure TPdfAttachmentList.Delete(AIndex: Integer);
var
  i: Integer;
  ok: FPDF_BOOL;
begin
  if (AIndex < 0) or (AIndex >= Length(FItems)) then
    raise EPdfiumError.Create(Format('Delete: attachment index %d is out of range (0..%d).', [AIndex, Length(FItems) - 1]));
  FDocument.Lock.Enter;
  try
    ok := FPDFDoc_DeleteAttachment(FDocument.Handle, AIndex);
  finally
    FDocument.Lock.Leave;
  end;
  if ok = 0 then
    raise EPdfiumError.Create(Format('Delete: could not delete attachment at index %d.', [AIndex]));
  FItems[AIndex].Free;
  for i := AIndex to High(FItems) - 1 do
    FItems[i] := FItems[i + 1];
  SetLength(FItems, Length(FItems) - 1);
end;

end.
