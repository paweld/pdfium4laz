unit PdfiumImages;

{$mode objfpc}{$H+}{$inline on}

interface

uses
  Classes, SysUtils, Types, Graphics, PdfiumLib, PdfiumCore, PdfiumRender;

type
  TPdfImageFormat = (ifPng, ifBmp, ifJpeg);

  TPdfImageItem = class
  private
    FPage: TPdfPage;
    FPageObj: FPDF_PAGEOBJECT;
    constructor Create(APage: TPdfPage; APageObj: FPDF_PAGEOBJECT);
  public
    function Bounds: TRectF;
    function PageIndex: Integer;
    function PixelWidth: Integer;
    function PixelHeight: Integer;
    { 0 if the image declares no DPI - not an error, per PDFium's own documented behavior for this call. }
    function HorizontalDPI: Double;
    function VerticalDPI: Double;
    function ToBitmap: TBitmap;
    procedure SaveToStream(ADest: TStream; AFormat: TPdfImageFormat = ifPng);
    procedure SaveToFile(const AOutputPath: String); overload;
    procedure SaveToFile(const AOutputPath: String; AFormat: TPdfImageFormat); overload;
  end;

  TPdfImageList = class
  private
    FItems: array of TPdfImageItem;
    function GetItem(AIndex: Integer): TPdfImageItem;
  public type
    TEnumerator = specialize TPdfEnumerator<TPdfImageItem>;
  public
    function GetEnumerator: TEnumerator;
    constructor CreateForPage(APage: TPdfPage);
    constructor CreateForDocument(ADocument: TPdfDocument);
    destructor Destroy; override;
    function Count: Integer;
    property Items[AIndex: Integer]: TPdfImageItem read GetItem; default;
  end;

implementation

{ TPdfImageItem }

constructor TPdfImageItem.Create(APage: TPdfPage; APageObj: FPDF_PAGEOBJECT);
begin
  inherited Create;
  FPage := APage;
  FPageObj := APageObj;
end;

function TPdfImageItem.Bounds: TRectF;
var
  l, b, r, t: Single;
begin
  FillChar(Result, SizeOf(Result), 0);
  FPage.Document.Lock.Enter;
  try
    if FPDFPageObj_GetBounds(FPageObj, l, b, r, t) <> 0 then
    begin
      Result.Left := l;
      Result.Bottom := b;
      Result.Right := r;
      Result.Top := t;
    end;
  finally
    FPage.Document.Lock.Leave;
  end;
end;

function TPdfImageItem.PageIndex: Integer;
begin
  Result := FPage.PageIndex;
end;

function TPdfImageItem.PixelWidth: Integer;
var
  w, h: LongWord;
begin
  FPage.Document.Lock.Enter;
  try
    if FPDFImageObj_GetImagePixelSize(FPageObj, w, h) = 0 then
      raise EPdfiumError.Create('Could not read the image object''s pixel size.');
    Result := w;
  finally
    FPage.Document.Lock.Leave;
  end;
end;

function TPdfImageItem.PixelHeight: Integer;
var
  w, h: LongWord;
begin
  FPage.Document.Lock.Enter;
  try
    if FPDFImageObj_GetImagePixelSize(FPageObj, w, h) = 0 then
      raise EPdfiumError.Create('Could not read the image object''s pixel size.');
    Result := h;
  finally
    FPage.Document.Lock.Leave;
  end;
end;

function TPdfImageItem.HorizontalDPI: Double;
var
  metadata: FPDF_IMAGEOBJ_METADATA;
begin
  FPage.Document.Lock.Enter;
  try
    if FPDFImageObj_GetImageMetadata(FPageObj, FPage.Handle, metadata) = 0 then
      raise EPdfiumError.Create('Could not read the image object''s metadata.');
    Result := metadata.horizontal_dpi;
  finally
    FPage.Document.Lock.Leave;
  end;
end;

function TPdfImageItem.VerticalDPI: Double;
var
  metadata: FPDF_IMAGEOBJ_METADATA;
begin
  FPage.Document.Lock.Enter;
  try
    if FPDFImageObj_GetImageMetadata(FPageObj, FPage.Handle, metadata) = 0 then
      raise EPdfiumError.Create('Could not read the image object''s metadata.');
    Result := metadata.vertical_dpi;
  finally
    FPage.Document.Lock.Leave;
  end;
end;

function TPdfImageItem.ToBitmap: TBitmap;
var
  fpdfBitmap: FPDF_BITMAP;
begin
  FPage.Document.Lock.Enter;
  try
    fpdfBitmap := FPDFImageObj_GetBitmap(FPageObj);
    if fpdfBitmap = nil then
      raise EPdfiumError.Create('Could not decode the image object bitmap.');
    try
      Result := PdfiumBitmapToTBitmap(fpdfBitmap);
    finally
      FPDFBitmap_Destroy(fpdfBitmap);
    end;
  finally
    FPage.Document.Lock.Leave;
  end;
end;

procedure TPdfImageItem.SaveToStream(ADest: TStream; AFormat: TPdfImageFormat = ifPng);
var
  bmp: TBitmap;
  png: TPortableNetworkGraphic;
  jpg: TJPEGImage;
begin
  bmp := ToBitmap;
  try
    case AFormat of
      ifBmp: bmp.SaveToStream(ADest);
      ifJpeg:
        begin
          jpg := TJPEGImage.Create;
          try
            jpg.Assign(bmp);
            jpg.SaveToStream(ADest);
          finally
            jpg.Free;
          end;
        end;
      else
        png := TPortableNetworkGraphic.Create;
        try
          png.Assign(bmp);
          png.SaveToStream(ADest);
        finally
          png.Free;
        end;
      end;
  finally
    bmp.Free;
  end;
end;

procedure TPdfImageItem.SaveToFile(const AOutputPath: String);
var
  ext: String;
  fmt: TPdfImageFormat;
begin
  ext := LowerCase(ExtractFileExt(AOutputPath));
  case ext of
    '.bmp': fmt := ifBmp;
    '.jpg', '.jpeg': fmt := ifJpeg;
    else
      fmt := ifPng;
  end;
  SaveToFile(AOutputPath, fmt);
end;

procedure TPdfImageItem.SaveToFile(const AOutputPath: String; AFormat: TPdfImageFormat);
var
  stream: TFileStream;
begin
  stream := TFileStream.Create(AOutputPath, fmCreate);
  try
    SaveToStream(stream, AFormat);
  finally
    stream.Free;
  end;
end;

{ TPdfImageList }

constructor TPdfImageList.CreateForPage(APage: TPdfPage);
var
  i, n: Integer;
  obj: FPDF_PAGEOBJECT;
begin
  inherited Create;
  n := 0;
  APage.Document.Lock.Enter;
  try
    for i := 0 to FPDFPage_CountObjects(APage.Handle) - 1 do
    begin
      obj := FPDFPage_GetObject(APage.Handle, i);
      if FPDFPageObj_GetType(obj) = FPDF_PAGEOBJ_IMAGE then
      begin
        SetLength(FItems, n + 1);
        FItems[n] := TPdfImageItem.Create(APage, obj);
        Inc(n);
      end;
    end;
  finally
    APage.Document.Lock.Leave;
  end;
end;

constructor TPdfImageList.CreateForDocument(ADocument: TPdfDocument);
var
  p, i, n: Integer;
  page: TPdfPage;
  obj: FPDF_PAGEOBJECT;
begin
  inherited Create;
  n := 0;
  ADocument.Lock.Enter;
  try
    for p := 0 to ADocument.PageCount - 1 do
    begin
      page := ADocument.Pages[p];
      for i := 0 to FPDFPage_CountObjects(page.Handle) - 1 do
      begin
        obj := FPDFPage_GetObject(page.Handle, i);
        if FPDFPageObj_GetType(obj) = FPDF_PAGEOBJ_IMAGE then
        begin
          SetLength(FItems, n + 1);
          FItems[n] := TPdfImageItem.Create(page, obj);
          Inc(n);
        end;
      end;
    end;
  finally
    ADocument.Lock.Leave;
  end;
end;

destructor TPdfImageList.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FItems) do
    FItems[i].Free;
  inherited Destroy;
end;

function TPdfImageList.Count: Integer;
begin
  Result := Length(FItems);
end;

function TPdfImageList.GetEnumerator: TEnumerator;
begin
  Result := TEnumerator.Create(@GetItem, Count);
end;

function TPdfImageList.GetItem(AIndex: Integer): TPdfImageItem;
begin
  if (AIndex < 0) or (AIndex >= Length(FItems)) then
    raise EPdfiumError.Create(Format('TPdfImageList[]: image index %d is out of range (0..%d).', [AIndex, Length(FItems) - 1]));
  Result := FItems[AIndex];
end;

end.
