unit PdfiumRender;

{$mode objfpc}{$H+}{$inline on}

interface

uses
  Classes, SysUtils, Types, Graphics, IntfGraphics, GraphType, PdfiumLib;

type
  TPdfColorScheme = record
    Enabled: Boolean;
    PathFillColor: TColor;
    PathStrokeColor: TColor;
    TextFillColor: TColor;
    TextStrokeColor: TColor;
    BackgroundColor: TColor;
    { TPdfViewer.InvertImageColors applies regardless of Enabled;
      TPdfThumbnailPanel.InvertImageColors only applies while Enabled is also True. }
    InvertImages: Boolean;
  end;

{ Caller retains ownership of AFpdfBitmap and must destroy it with FPDFBitmap_Destroy. }
function PdfiumBitmapToTBitmap(AFpdfBitmap: FPDF_BITMAP): TBitmap;

{ Always repaints the real image even when AInvert is False, to work around
  a confirmed PDFium bug: FPDF_RenderPageBitmapWithColorScheme_Start can
  substitute a flat fill color for some images instead of drawing them.

  KNOWN GAP: an object drawn on top of an image later in the same content
  stream (e.g. a decorative border) gets silently overwritten, since this
  only knows the image's own placement, not what was drawn over it after. }
procedure CompositeImagePixels(ADestBitmap: TBitmap; ADestRect: TRect; ASrcBitmap: FPDF_BITMAP; const AMatrix: FS_MATRIX;
  APageWidth, APageHeight: Double; AJobW, AJobH: Integer; AInvert: Boolean);

implementation

function PdfiumBitmapToTBitmap(AFpdfBitmap: FPDF_BITMAP): TBitmap;
var
  w, h, stride, fmt, x, y: Integer;
  srcBuf: PByte;
  intfImg: TLazIntfImage;
  rawDesc: TRawImageDescription;
  srcRow, dstRow: PByte;
  gray: Byte;
begin
  w := FPDFBitmap_GetWidth(AFpdfBitmap);
  h := FPDFBitmap_GetHeight(AFpdfBitmap);
  stride := FPDFBitmap_GetStride(AFpdfBitmap);
  fmt := FPDFBitmap_GetFormat(AFpdfBitmap);
  srcBuf := PByte(FPDFBitmap_GetBuffer(AFpdfBitmap));
  rawDesc.Init_BPP32_B8G8R8A8_BIO_TTB(w, h);
  intfImg := TLazIntfImage.Create(0, 0);
  try
    intfImg.DataDescription := rawDesc;
    intfImg.SetSize(w, h);
    for y := 0 to h - 1 do
    begin
      srcRow := srcBuf + y * stride;
      dstRow := PByte(intfImg.GetDataLineStart(y));
      case fmt of
        FPDFBitmap_Gray:
          for x := 0 to w - 1 do
          begin
            gray := srcRow[x];
            dstRow[x * 4] := gray;
            dstRow[x * 4 + 1] := gray;
            dstRow[x * 4 + 2] := gray;
            dstRow[x * 4 + 3] := 255;
          end;
        FPDFBitmap_BGR:
          for x := 0 to w - 1 do
          begin
            dstRow[x * 4] := srcRow[x * 3];
            dstRow[x * 4 + 1] := srcRow[x * 3 + 1];
            dstRow[x * 4 + 2] := srcRow[x * 3 + 2];
            dstRow[x * 4 + 3] := 255;
          end;
      else
        { BGRx / BGRA already lay out 4 bytes per pixel in the target order. }
        Move(srcRow^, dstRow^, w * 4);
        if fmt = FPDFBitmap_BGRx then
        begin
          for x := 0 to w - 1 do
            dstRow[x * 4 + 3] := 255;
        end;
      end;
    end;
    Result := TBitmap.Create;
    Result.PixelFormat := pf32bit;
    Result.LoadFromIntfImage(intfImg);
  finally
    intfImg.Free;
  end;
end;

procedure CompositeImagePixels(ADestBitmap: TBitmap; ADestRect: TRect; ASrcBitmap: FPDF_BITMAP; const AMatrix: FS_MATRIX;
  APageWidth, APageHeight: Double; AJobW, AJobH: Integer; AInvert: Boolean);
var
  destImg: TLazIntfImage;
  destRow: PByte;
  srcBuf: PByte;
  srcW, srcH, srcStride, srcFmt: Integer;
  destX, destY: Integer;
  clipRect: TRect;
  det, sr, sg, sb, sa, t, newVal: Double;

  { ix/iy must already be clamped to the bitmap's own bounds. }
  procedure RawSrcPixel(ix, iy: Integer; out AR, AG, AB, AA: Double);
  var
    p: PByte;
  begin
    case srcFmt of
      FPDFBitmap_Gray:
        begin
          p := srcBuf + iy * srcStride + ix;
          AR := p[0]; AG := p[0]; AB := p[0]; AA := 255;
        end;
      FPDFBitmap_BGR:
        begin
          p := srcBuf + iy * srcStride + ix * 3;
          AB := p[0]; AG := p[1]; AR := p[2]; AA := 255;
        end;
      FPDFBitmap_BGRA:
        begin
          p := srcBuf + iy * srcStride + ix * 4;
          AB := p[0]; AG := p[1]; AR := p[2]; AA := p[3];
        end;
    else
      { BGRx: 4 bytes/pixel, 4th is unused padding - always opaque. }
      begin
        p := srcBuf + iy * srcStride + ix * 4;
        AB := p[0]; AG := p[1]; AR := p[2]; AA := 255;
      end;
    end;
  end;

  { ax/ay may be slightly outside [0, srcW]/[0, srcH] at the image's own edge - clamped here. }
  procedure SampleSrcRGBA(ax, ay: Double; out AR, AG, AB, AA: Double);
  var
    ix0, iy0, ix1, iy1: Integer;
    itx, ity: Double;
    r00, g00, b00, a00, r10, g10, b10, a10: Double;
    r01, g01, b01, a01, r11, g11, b11, a11: Double;
    rTop, gTop, bTop, aTop, rBottom, gBottom, bBottom, aBottom: Double;
  begin
    if ax < 0 then ax := 0;
    if ay < 0 then ay := 0;
    ix0 := Trunc(ax);
    if ix0 > srcW - 1 then ix0 := srcW - 1;
    ix1 := ix0 + 1;
    if ix1 > srcW - 1 then ix1 := srcW - 1;
    itx := ax - ix0;
    iy0 := Trunc(ay);
    if iy0 > srcH - 1 then iy0 := srcH - 1;
    iy1 := iy0 + 1;
    if iy1 > srcH - 1 then iy1 := srcH - 1;
    ity := ay - iy0;
    RawSrcPixel(ix0, iy0, r00, g00, b00, a00);
    RawSrcPixel(ix1, iy0, r10, g10, b10, a10);
    RawSrcPixel(ix0, iy1, r01, g01, b01, a01);
    RawSrcPixel(ix1, iy1, r11, g11, b11, a11);
    rTop := r00 + (r10 - r00) * itx; rBottom := r01 + (r11 - r01) * itx;
    gTop := g00 + (g10 - g00) * itx; gBottom := g01 + (g11 - g01) * itx;
    bTop := b00 + (b10 - b00) * itx; bBottom := b01 + (b11 - b01) * itx;
    aTop := a00 + (a10 - a00) * itx; aBottom := a01 + (a11 - a01) * itx;
    AR := rTop + (rBottom - rTop) * ity;
    AG := gTop + (gBottom - gTop) * ity;
    AB := bTop + (bBottom - bTop) * ity;
    AA := aTop + (aBottom - aTop) * ity;
  end;

  { v follows PDF's page-space convention (0 = bottom, 1 = top) - the caller flips it to a top-down source row. }
  procedure DeviceToUnitSquare(px, py: Integer; out u, v: Double);
  var
    pageX, pageY: Double;
  begin
    pageX := (px + 0.5) * APageWidth / AJobW;
    pageY := APageHeight - (py + 0.5) * APageHeight / AJobH;
    u := (AMatrix.d * (pageX - AMatrix.e) - AMatrix.c * (pageY - AMatrix.f)) / det;
    v := (-AMatrix.b * (pageX - AMatrix.e) + AMatrix.a * (pageY - AMatrix.f)) / det;
  end;

var
  u, v: Double;
begin
  det := AMatrix.a * AMatrix.d - AMatrix.b * AMatrix.c;
  if Abs(det) < 1e-9 then
    exit; { Degenerate (non-invertible) placement matrix - nothing sane to map. }
  clipRect := ADestRect;
  IntersectRect(clipRect, clipRect, Rect(0, 0, ADestBitmap.Width, ADestBitmap.Height));
  if (clipRect.Right <= clipRect.Left) or (clipRect.Bottom <= clipRect.Top) then
    exit;
  srcW := FPDFBitmap_GetWidth(ASrcBitmap);
  srcH := FPDFBitmap_GetHeight(ASrcBitmap);
  if (srcW <= 0) or (srcH <= 0) then
    exit;
  srcStride := FPDFBitmap_GetStride(ASrcBitmap);
  srcFmt := FPDFBitmap_GetFormat(ASrcBitmap);
  srcBuf := PByte(FPDFBitmap_GetBuffer(ASrcBitmap));
  destImg := ADestBitmap.CreateIntfImage;
  try
    for destY := clipRect.Top to clipRect.Bottom - 1 do
    begin
      destRow := PByte(destImg.GetDataLineStart(destY));
      for destX := clipRect.Left to clipRect.Right - 1 do
      begin
        DeviceToUnitSquare(destX, destY, u, v);
        if (u < 0) or (u > 1) or (v < 0) or (v > 1) then
          continue;
        SampleSrcRGBA(u * srcW - 0.5, (1 - v) * srcH - 0.5, sr, sg, sb, sa);
        if sa <= 0 then
          continue;
        t := sa / 255.0;
        if AInvert then
        begin
          sr := 255 - sr;
          sg := 255 - sg;
          sb := 255 - sb;
        end;
        newVal := destRow[destX * 4] + t * (sb - destRow[destX * 4]);
        if newVal < 0 then newVal := 0 else if newVal > 255 then newVal := 255;
        destRow[destX * 4] := Round(newVal);
        newVal := destRow[destX * 4 + 1] + t * (sg - destRow[destX * 4 + 1]);
        if newVal < 0 then newVal := 0 else if newVal > 255 then newVal := 255;
        destRow[destX * 4 + 1] := Round(newVal);
        newVal := destRow[destX * 4 + 2] + t * (sr - destRow[destX * 4 + 2]);
        if newVal < 0 then newVal := 0 else if newVal > 255 then newVal := 255;
        destRow[destX * 4 + 2] := Round(newVal);
      end;
    end;
    ADestBitmap.LoadFromIntfImage(destImg);
  finally
    destImg.Free;
  end;
end;

end.
