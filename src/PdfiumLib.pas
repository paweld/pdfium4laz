{

  MIT License

  Copyright (c) 2026 Paweł Dmitruk ( https://github.com/paweld )

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.

}
{----------------------------------------
  Minimum version of the pdfium library: 6036
  Compiled libraries can be downloaded from:
    https://github.com/bblanchon/pdfium-binaries/releases
----------------------------------------}

unit PdfiumLib;

{$mode objfpc}{$H+}{$inline on}

interface

uses
  Classes, SysUtils, Math, dynlibs, ctypes,
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  syncobjs;

{$PACKRECORDS C}

type
  FPDF_DOCUMENT = Pointer;
  FPDF_PAGE = Pointer;
  FPDF_BITMAP = Pointer;
  FPDF_TEXTPAGE = Pointer;
  FPDF_SCHHANDLE = Pointer;
  FPDF_BOOKMARK = Pointer;
  FPDF_ACTION = Pointer;
  FPDF_DEST = Pointer;
  FPDF_LINK = Pointer;
  FPDF_ATTACHMENT = Pointer;
  FPDF_PAGEOBJECT = Pointer;

  FPDF_BOOL = Integer;
  { C "unsigned long": 32-bit on Windows, but 64-bit on Linux/macOS x86_64/aarch64 (LP64).
    Must not be LongWord - records (FPDF_COLORSCHEME, FPDF_FILEACCESS) and pointer
    params (FPDFAttachment_GetFile's out_buflen) would get the wrong layout there. }
  {$IFDEF WINDOWS}
  FPDF_ULONG = LongWord; { ctypes.culong is wrongly 64-bit on Win64/aarch64 }
  {$ELSE}
  FPDF_ULONG = culong;
  {$ENDIF}
  FPDF_DWORD = FPDF_ULONG;

  FS_RECTF = record
    Left, Top, Right, Bottom: Single;
  end;
  PFS_RECTF = ^FS_RECTF;

  FS_MATRIX = record
    a, b, c, d, e, f: Single;
  end;
  PFS_MATRIX = ^FS_MATRIX;

  TFPDF_GetBlockCallback = function(AParam: Pointer; APosition: FPDF_ULONG; ABuf: PByte; ASize: FPDF_ULONG): Integer; cdecl;

  FPDF_FILEACCESS = record
    m_FileLen: FPDF_ULONG;
    m_GetBlock: TFPDF_GetBlockCallback;
    m_Param: Pointer;
  end;
  PFPDF_FILEACCESS = ^FPDF_FILEACCESS;

  PFPDF_FILEWRITE = ^FPDF_FILEWRITE;
  TFPDF_WriteBlockCallback = function(AThis: PFPDF_FILEWRITE; AData: Pointer; ASize: FPDF_ULONG): Integer; cdecl;

  FPDF_FILEWRITE = record
    version: Integer;
    WriteBlock: TFPDF_WriteBlockCallback;
  end;

  { Field order must match fpdf_edit.h's FPDF_IMAGEOBJ_METADATA exactly. }
  FPDF_IMAGEOBJ_METADATA = record
    width: LongWord;
    height: LongWord;
    horizontal_dpi: Single;
    vertical_dpi: Single;
    bits_per_pixel: LongWord;
    colorspace: Integer;
    marked_content_id: Integer;
  end;
  PFPDF_IMAGEOBJ_METADATA = ^FPDF_IMAGEOBJ_METADATA;

  FS_SIZEF = record
    width: Single;
    height: Single;
  end;
  PFS_SIZEF = ^FS_SIZEF;

  { Each field is a 32-bit ARGB color; field order must match fpdfview.h's
    FPDF_COLORSCHEME_ exactly. }
  FPDF_COLORSCHEME = record
    path_fill_color: FPDF_DWORD;
    path_stroke_color: FPDF_DWORD;
    text_fill_color: FPDF_DWORD;
    text_stroke_color: FPDF_DWORD;
  end;
  PFPDF_COLORSCHEME = ^FPDF_COLORSCHEME;

  { fpdf_progressive.h's _IFSDK_PAUSE. This PDFium build returns
    FPDF_RENDER_FAILED if pause is nil - always pass a real callback. }
  TFPDF_NeedToPauseNowCallback = function(pThis: Pointer): FPDF_BOOL; cdecl;

  IFSDK_PAUSE = record
    version: Integer;
    NeedToPauseNow: TFPDF_NeedToPauseNowCallback;
    user: Pointer;
  end;
  PIFSDK_PAUSE = ^IFSDK_PAUSE;

{$PACKRECORDS DEFAULT}

const
  FPDF_ERR_SUCCESS  = 0;
  FPDF_ERR_UNKNOWN  = 1;
  FPDF_ERR_FILE     = 2;
  FPDF_ERR_FORMAT   = 3;
  FPDF_ERR_PASSWORD = 4;
  FPDF_ERR_SECURITY = 5;
  FPDF_ERR_PAGE     = 6;

  FPDF_ANNOT                    = $01;
  FPDF_LCD_TEXT                 = $02;
  FPDF_NO_NATIVETEXT            = $04;
  FPDF_GRAYSCALE                = $08;
  FPDF_RENDER_LIMITEDIMAGECACHE = $200;
  FPDF_RENDER_FORCEHALFTONE     = $400;
  FPDF_PRINTING                 = $800;
  FPDF_RENDER_NO_SMOOTHTEXT     = $1000;
  FPDF_RENDER_NO_SMOOTHIMAGE    = $2000;
  FPDF_RENDER_NO_SMOOTHPATH     = $4000;
  FPDF_REVERSE_BYTE_ORDER       = $10;

  FPDFBitmap_Unknown = 0;
  FPDFBitmap_Gray     = 1;
  FPDFBitmap_BGR      = 2;
  FPDFBitmap_BGRx     = 3;
  FPDFBitmap_BGRA     = 4;

  FPDF_PAGEOBJ_UNKNOWN  = 0;
  FPDF_PAGEOBJ_TEXT     = 1;
  FPDF_PAGEOBJ_PATH     = 2;
  FPDF_PAGEOBJ_IMAGE    = 3;
  FPDF_PAGEOBJ_SHADING  = 4;
  FPDF_PAGEOBJ_FORM     = 5;

  PDFACTION_UNSUPPORTED = 0;
  PDFACTION_GOTO        = 1;
  PDFACTION_REMOTEGOTO  = 2;
  PDFACTION_URI         = 3;
  PDFACTION_LAUNCH      = 4;

  { Already bit-shifted - test directly against the raw permission DWORD. }
  FPDF_PERM_PRINT           = 1 shl 2;
  FPDF_PERM_MODIFY          = 1 shl 3;
  FPDF_PERM_COPY            = 1 shl 4;
  FPDF_PERM_ANNOT_FORMS     = 1 shl 5;
  FPDF_PERM_FILL_FORMS      = 1 shl 8;
  FPDF_PERM_EXTRACT_ACCESS  = 1 shl 9;
  FPDF_PERM_ASSEMBLE        = 1 shl 10;
  FPDF_PERM_PRINT_HIGH      = 1 shl 11;

  FPDF_MATCHCASE      = $00000001;
  FPDF_MATCHWHOLEWORD = $00000002;
  FPDF_CONSECUTIVE    = $00000004;

  FPDF_INCREMENTAL     = 1 shl 0;
  FPDF_NO_INCREMENTAL  = 1 shl 1;
  FPDF_REMOVE_SECURITY = 1 shl 2;

  FILEIDTYPE_PERMANENT = 0;
  FILEIDTYPE_CHANGING  = 1;

  FORMTYPE_NONE           = 0;
  FORMTYPE_ACRO_FORM      = 1;
  FORMTYPE_XFA_FULL       = 2;
  FORMTYPE_XFA_FOREGROUND = 3;

  FPDF_RENDER_READY        = 0;
  FPDF_RENDER_TOBECONTINUED = 1;
  FPDF_RENDER_DONE         = 2;
  FPDF_RENDER_FAILED       = 3;

  FPDF_OBJECT_UNKNOWN    = 0;
  FPDF_OBJECT_BOOLEAN    = 1;
  FPDF_OBJECT_NUMBER     = 2;
  FPDF_OBJECT_STRING     = 3;
  FPDF_OBJECT_NAME       = 4;
  FPDF_OBJECT_ARRAY      = 5;
  FPDF_OBJECT_DICTIONARY = 6;
  FPDF_OBJECT_STREAM     = 7;
  FPDF_OBJECT_NULLOBJ    = 8;
  FPDF_OBJECT_REFERENCE  = 9;

type
  EPdfiumError = class(Exception)
  private
    FErrorCode: LongWord;
  public
    constructor Create(const AMessage: String; AErrorCode: LongWord = 0);
    property ErrorCode: LongWord read FErrorCode;
  end;

  { TPdfiumLock }

  TPdfiumLock = class(TCriticalSection)
  public
    procedure Acquire; override;
  end;

{ Library initialisation. Safe to call multiple times (ref-counted); the
  underlying library is only actually loaded on the first call and unloaded
  once the ref count returns to zero. }
procedure PdfiumInitialize(const ALibraryPath: String = '');
procedure PdfiumFinalize;
function PdfiumLoaded: Boolean;
function PdfiumVersion: String;

{ Always False on non-Windows - PDFium does not export FPDF_RenderPage there. }
function PdfiumRenderPageAvailable: Boolean;

procedure PdfiumCheckLoaded;

{ No-op if the library is already loaded, by auto-discovery or an explicit
  PdfiumInitialize(APath) call - never overrides an explicit path. }
procedure PdfiumEnsureInitialized;

{ PDFium is not thread-safe against concurrent calls on the SAME document.
  TPdfDocument.Lock (PdfiumCore.pas) is the per-document lock everything else
  in this package uses; this one remains only for PdfiumMerge.pas's own
  temporary/shell documents, which never get a TPdfDocument wrapper. }
var
  PdfiumGlobalLock: TCriticalSection;
  { Set while a foreground render (TPdfRenderWorker, PdfiumViewer.pas) wants
    the lock; TPdfThumbnailCache checks this between pages and stands aside
    while it is non-zero, so background thumbnail work cannot starve the
    visible page's own render. }
  PdfiumHighPriorityRequests: LongInt = 0;

var
  FPDF_InitLibrary: procedure; cdecl;
  FPDF_DestroyLibrary: procedure; cdecl;
  FPDF_GetLastError: function: FPDF_ULONG; cdecl;
  FPDF_LoadDocument: function(file_path: PAnsiChar; password: PAnsiChar): FPDF_DOCUMENT; cdecl;
  FPDF_LoadMemDocument64: function(data_buf: Pointer; size: SizeUInt; password: PAnsiChar): FPDF_DOCUMENT; cdecl;
  FPDF_LoadCustomDocument: function(pFileAccess: PFPDF_FILEACCESS; password: PAnsiChar): FPDF_DOCUMENT; cdecl;
  FPDF_CloseDocument: procedure(document: FPDF_DOCUMENT); cdecl;
  FPDF_GetDocPermissions: function(document: FPDF_DOCUMENT): FPDF_ULONG; cdecl;
  FPDF_GetSecurityHandlerRevision: function(document: FPDF_DOCUMENT): Integer; cdecl;
  FPDF_GetMetaText: function(document: FPDF_DOCUMENT; tag: PAnsiChar; buffer: Pointer; buflen: FPDF_ULONG): FPDF_ULONG; cdecl;
  FPDF_GetDocUserPermissions: function(document: FPDF_DOCUMENT): FPDF_ULONG; cdecl;
  FPDF_GetFileVersion: function(doc: FPDF_DOCUMENT; out fileVersion: Integer): FPDF_BOOL; cdecl;
  FPDF_GetPageCount: function(document: FPDF_DOCUMENT): Integer; cdecl;
  FPDF_GetPageSizeByIndexF: function(document: FPDF_DOCUMENT; page_index: Integer; out size: FS_SIZEF): FPDF_BOOL; cdecl;
  FPDF_LoadPage: function(document: FPDF_DOCUMENT; page_index: Integer): FPDF_PAGE; cdecl;
  FPDF_ClosePage: procedure(page: FPDF_PAGE); cdecl;
  FPDF_GetPageWidthF: function(page: FPDF_PAGE): Single; cdecl;
  FPDF_GetPageHeightF: function(page: FPDF_PAGE): Single; cdecl;
  FPDFPage_GetRotation: function(page: FPDF_PAGE): Integer; cdecl;
  FPDFPage_SetRotation: procedure(page: FPDF_PAGE; rotate: Integer); cdecl;
  FPDFPage_HasTransparency: function(page: FPDF_PAGE): FPDF_BOOL; cdecl;
  FPDF_RenderPageBitmap: procedure(bitmap: FPDF_BITMAP; page: FPDF_PAGE; start_x, start_y, size_x, size_y, rotate, flags: Integer); cdecl;
  {$IFDEF WINDOWS}
  { PDFium does not export this on non-Windows builds - bound via
    BindOptionalProc so its absence there does not fail loading the library. }
  FPDF_RenderPage: function(dc: HDC; page: FPDF_PAGE; start_x, start_y, size_x, size_y, rotate, flags: Integer): FPDF_BOOL; cdecl;
  {$ENDIF}
  FPDFBitmap_CreateEx: function(width, height, format: Integer; first_scan: Pointer; stride: Integer): FPDF_BITMAP; cdecl;
  FPDFBitmap_FillRect: function(bitmap: FPDF_BITMAP; left, top, width, height: Integer; color: FPDF_DWORD): FPDF_BOOL; cdecl;
  FPDFBitmap_GetBuffer: function(bitmap: FPDF_BITMAP): Pointer; cdecl;
  FPDFBitmap_GetFormat: function(bitmap: FPDF_BITMAP): Integer; cdecl;
  FPDFBitmap_GetWidth: function(bitmap: FPDF_BITMAP): Integer; cdecl;
  FPDFBitmap_GetHeight: function(bitmap: FPDF_BITMAP): Integer; cdecl;
  FPDFBitmap_GetStride: function(bitmap: FPDF_BITMAP): Integer; cdecl;
  FPDFBitmap_Destroy: procedure(bitmap: FPDF_BITMAP); cdecl;

  FPDFText_LoadPage: function(page: FPDF_PAGE): FPDF_TEXTPAGE; cdecl;
  FPDFText_ClosePage: procedure(text_page: FPDF_TEXTPAGE); cdecl;
  FPDFText_CountChars: function(text_page: FPDF_TEXTPAGE): Integer; cdecl;
  FPDFText_GetUnicode: function(text_page: FPDF_TEXTPAGE; index: Integer): LongWord; cdecl;
  FPDFText_GetFontSize: function(text_page: FPDF_TEXTPAGE; index: Integer): Double; cdecl;
  FPDFText_GetCharBox: function(text_page: FPDF_TEXTPAGE; index: Integer; out left, right, bottom, top: Double): FPDF_BOOL; cdecl;
  FPDFText_GetCharOrigin: function(text_page: FPDF_TEXTPAGE; index: Integer; out x, y: Double): FPDF_BOOL; cdecl;
  FPDFText_GetCharIndexAtPos: function(text_page: FPDF_TEXTPAGE; x, y, xTolerance, yTolerance: Double): Integer; cdecl;
  FPDFText_GetText: function(text_page: FPDF_TEXTPAGE; start_index, count: Integer; AResult: PWideChar): Integer; cdecl;
  FPDFText_CountRects: function(text_page: FPDF_TEXTPAGE; start_index, count: Integer): Integer; cdecl;
  FPDFText_GetRect: function(text_page: FPDF_TEXTPAGE; rect_index: Integer; out left, top, right, bottom: Double): FPDF_BOOL; cdecl;
  FPDFText_GetBoundedText: function(text_page: FPDF_TEXTPAGE; left, top, right, bottom: Double; buffer: PWideChar; buflen: Integer): Integer; cdecl;
  FPDFText_FindStart: function(text_page: FPDF_TEXTPAGE; findwhat: PWideChar; flags: FPDF_ULONG; start_index: Integer): FPDF_SCHHANDLE; cdecl;
  FPDFText_FindNext: function(handle: FPDF_SCHHANDLE): FPDF_BOOL; cdecl;
  FPDFText_FindPrev: function(handle: FPDF_SCHHANDLE): FPDF_BOOL; cdecl;
  FPDFText_GetSchResultIndex: function(handle: FPDF_SCHHANDLE): Integer; cdecl;
  FPDFText_GetSchCount: function(handle: FPDF_SCHHANDLE): Integer; cdecl;
  FPDFText_FindClose: procedure(handle: FPDF_SCHHANDLE); cdecl;

  FPDFBookmark_GetFirstChild: function(document: FPDF_DOCUMENT; bookmark: FPDF_BOOKMARK): FPDF_BOOKMARK; cdecl;
  FPDFBookmark_GetNextSibling: function(document: FPDF_DOCUMENT; bookmark: FPDF_BOOKMARK): FPDF_BOOKMARK; cdecl;
  FPDFBookmark_GetTitle: function(bookmark: FPDF_BOOKMARK; buffer: Pointer; buflen: FPDF_ULONG): FPDF_ULONG; cdecl;
  FPDFBookmark_GetDest: function(document: FPDF_DOCUMENT; bookmark: FPDF_BOOKMARK): FPDF_DEST; cdecl;
  FPDFBookmark_GetAction: function(bookmark: FPDF_BOOKMARK): FPDF_ACTION; cdecl;
  FPDFAction_GetType: function(action: FPDF_ACTION): FPDF_ULONG; cdecl;
  FPDFAction_GetDest: function(document: FPDF_DOCUMENT; action: FPDF_ACTION): FPDF_DEST; cdecl;
  FPDFAction_GetFilePath: function(action: FPDF_ACTION; buffer: Pointer; buflen: FPDF_ULONG): FPDF_ULONG; cdecl;
  FPDFAction_GetURIPath: function(document: FPDF_DOCUMENT; action: FPDF_ACTION; buffer: Pointer; buflen: FPDF_ULONG): FPDF_ULONG; cdecl;
  FPDFDest_GetDestPageIndex: function(document: FPDF_DOCUMENT; dest: FPDF_DEST): Integer; cdecl;
  FPDFDest_GetLocationInPage: function(dest: FPDF_DEST; out hasXVal, hasYVal, hasZoomVal: FPDF_BOOL; out x, y, zoom: Single): FPDF_BOOL; cdecl;
  FPDFLink_Enumerate: function(page: FPDF_PAGE; var start_pos: Integer; out link_annot: FPDF_LINK): FPDF_BOOL; cdecl;
  FPDFLink_GetDest: function(document: FPDF_DOCUMENT; link: FPDF_LINK): FPDF_DEST; cdecl;
  FPDFLink_GetAction: function(link: FPDF_LINK): FPDF_ACTION; cdecl;
  FPDFLink_GetAnnotRect: function(link_annot: FPDF_LINK; out rect: FS_RECTF): FPDF_BOOL; cdecl;
  FPDFBookmark_GetColor: function(bookmark: FPDF_BOOKMARK; out R, G, B: Single): FPDF_BOOL; cdecl;
  FPDF_GetFileIdentifier: function(document: FPDF_DOCUMENT; id_type: Integer; buffer: Pointer; buflen: FPDF_ULONG): FPDF_ULONG; cdecl;
  FPDF_GetPageLabel: function(document: FPDF_DOCUMENT; page_index: Integer; buffer: Pointer; buflen: FPDF_ULONG): FPDF_ULONG; cdecl;

  FPDFCatalog_GetLanguage: function(document: FPDF_DOCUMENT; buffer: Pointer; buflen: FPDF_ULONG): FPDF_ULONG; cdecl;

  FPDF_GetFormType: function(document: FPDF_DOCUMENT): Integer; cdecl;

  FPDFDoc_GetAttachmentCount: function(document: FPDF_DOCUMENT): Integer; cdecl;
  FPDFDoc_AddAttachment: function(document: FPDF_DOCUMENT; name: PWideChar): FPDF_ATTACHMENT; cdecl;
  FPDFDoc_GetAttachment: function(document: FPDF_DOCUMENT; index: Integer): FPDF_ATTACHMENT; cdecl;
  FPDFDoc_DeleteAttachment: function(document: FPDF_DOCUMENT; index: Integer): FPDF_BOOL; cdecl;
  FPDFAttachment_GetName: function(attachment: FPDF_ATTACHMENT; buffer: Pointer; buflen: FPDF_ULONG): FPDF_ULONG; cdecl;
  FPDFAttachment_HasKey: function(attachment: FPDF_ATTACHMENT; key: PAnsiChar): FPDF_BOOL; cdecl;
  FPDFAttachment_GetValueType: function(attachment: FPDF_ATTACHMENT; key: PAnsiChar): Integer; cdecl;
  FPDFAttachment_SetStringValue: function(attachment: FPDF_ATTACHMENT; key: PAnsiChar; value: PWideChar): FPDF_BOOL; cdecl;
  FPDFAttachment_GetStringValue: function(attachment: FPDF_ATTACHMENT; key: PAnsiChar; buffer: Pointer; buflen: FPDF_ULONG): FPDF_ULONG; cdecl;
  FPDFAttachment_GetSubtype: function(attachment: FPDF_ATTACHMENT; buffer: Pointer; buflen: FPDF_ULONG): FPDF_ULONG; cdecl;
  FPDFAttachment_SetFile: function(attachment: FPDF_ATTACHMENT; document: FPDF_DOCUMENT; contents: Pointer; len: FPDF_ULONG): FPDF_BOOL; cdecl;
  FPDFAttachment_GetFile: function(attachment: FPDF_ATTACHMENT; buffer: Pointer; buflen: FPDF_ULONG; out out_buflen: FPDF_ULONG): FPDF_BOOL; cdecl;

  FPDF_CreateNewDocument: function: FPDF_DOCUMENT; cdecl;
  FPDF_MovePages: function(document: FPDF_DOCUMENT; page_indices: PInteger; page_indices_len: FPDF_ULONG; dest_page_index: Integer): FPDF_BOOL; cdecl;
  FPDFPage_CountObjects: function(page: FPDF_PAGE): Integer; cdecl;
  FPDFPage_GetObject: function(page: FPDF_PAGE; index: Integer): FPDF_PAGEOBJECT; cdecl;
  FPDFPageObj_GetType: function(page_object: FPDF_PAGEOBJECT): Integer; cdecl;
  FPDFPageObj_GetBounds: function(page_object: FPDF_PAGEOBJECT; out left, bottom, right, top: Single): FPDF_BOOL; cdecl;
  { Local unit square [0,1]x[0,1] to page space: x'=a*x+c*y+e, y'=b*x+d*y+f. }
  FPDFPageObj_GetMatrix: function(page_object: FPDF_PAGEOBJECT; out matrix: FS_MATRIX): FPDF_BOOL; cdecl;
  { Ignores the image's own mask/transparency - use FPDFImageObj_GetRenderedBitmap instead where that matters. }
  FPDFImageObj_GetBitmap: function(image_object: FPDF_PAGEOBJECT): FPDF_BITMAP; cdecl;
  FPDFImageObj_GetRenderedBitmap: function(document: FPDF_DOCUMENT; page: FPDF_PAGE; image_object: FPDF_PAGEOBJECT): FPDF_BITMAP; cdecl;
  FPDFImageObj_GetImageMetadata: function(image_object: FPDF_PAGEOBJECT; page: FPDF_PAGE; out metadata: FPDF_IMAGEOBJ_METADATA): FPDF_BOOL; cdecl;
  FPDFImageObj_GetImagePixelSize: function(image_object: FPDF_PAGEOBJECT; out width, height: LongWord): FPDF_BOOL; cdecl;

  FPDFPage_Delete: procedure(document: FPDF_DOCUMENT; page_index: Integer); cdecl;

  FPDF_ImportPages: function(dest_doc, src_doc: FPDF_DOCUMENT; pagerange: PAnsiChar; index: Integer): FPDF_BOOL; cdecl;
  FPDF_ImportPagesByIndex: function(dest_doc, src_doc: FPDF_DOCUMENT; page_indices: PInteger; length: FPDF_ULONG; index: Integer): FPDF_BOOL; cdecl;

  FPDF_SaveAsCopy: function(document: FPDF_DOCUMENT; file_write: PFPDF_FILEWRITE; flags: FPDF_DWORD): FPDF_BOOL; cdecl;
  FPDF_SaveWithVersion: function(document: FPDF_DOCUMENT; file_write: PFPDF_FILEWRITE; flags: FPDF_DWORD; file_version: Integer): FPDF_BOOL; cdecl;

  FPDF_RenderPageBitmapWithColorScheme_Start: function(bitmap: FPDF_BITMAP; page: FPDF_PAGE; start_x, start_y, size_x, size_y, rotate, flags: Integer;
    color_scheme: PFPDF_COLORSCHEME; pause: PIFSDK_PAUSE): Integer; cdecl;
  FPDF_RenderPage_Continue: function(page: FPDF_PAGE; pause: PIFSDK_PAUSE): Integer; cdecl;
  FPDF_RenderPage_Close: procedure(page: FPDF_PAGE); cdecl;

  FPDFPage_GetThumbnailAsBitmap: function(page: FPDF_PAGE): FPDF_BITMAP; cdecl;

implementation

type
  TPdfiumStringArray = array of String;

var
  gLibHandle: TLibHandle = NilHandle;
  gRefCount: Integer = 0;
  gLibraryPath: String = '';

function PdfiumArchTag: String;
begin
  Result := '';
  {$IFDEF CPUX86_64}
  Result := 'x64';
  {$ENDIF}
  {$IFDEF CPUI386}
  Result := 'x86';
  {$ENDIF}
  {$IFDEF CPUAARCH64}
  Result := 'arm64';
  {$ENDIF}
end;

function PdfiumCandidateFileNames: TPdfiumStringArray;
var
  arch: String;
  n: Integer;

  procedure Add(const AName: String);
  begin
    SetLength(Result, n + 1);
    Result[n] := AName;
    Inc(n);
  end;

begin
  n := 0;
  SetLength(Result, 0);
  arch := PdfiumArchTag;
  {$IFDEF WINDOWS}
  if arch <> '' then
  begin
    Add('pdfium-' + arch + '.dll');
    Add('pdfium_' + arch + '.dll');
  end;
  Add('pdfium.dll');
  {$ELSE}
  {$IFDEF DARWIN}
  if arch <> '' then
  begin
    Add('libpdfium-' + arch + '.dylib');
    Add('libpdfium_' + arch + '.dylib');
  end;
  Add('libpdfium.dylib');
  {$ELSE}
  if arch <> '' then
  begin
    Add('libpdfium-' + arch + '.so');
    Add('libpdfium_' + arch + '.so');
  end;
  Add('libpdfium.so');
  {$ENDIF}
  {$ENDIF}
end;

{ The final empty-String entry is not a directory - it makes LoadLibrary/dlopen
  fall back to the OS's own standard search path. }
function PdfiumCandidateDirs: TPdfiumStringArray;
var
  exeDir: String;
  {$IFDEF DARWIN}
  contentsDir: String;
  {$ENDIF}
begin
  exeDir := ExtractFilePath(ParamStr(0));
  {$IFDEF DARWIN}
  contentsDir := ExtractFilePath(ExcludeTrailingPathDelimiter(exeDir));
  SetLength(Result, 5);
  Result[0] := exeDir;
  Result[1] := exeDir + 'lib' + PathDelim;
  Result[2] := contentsDir + 'Frameworks' + PathDelim;
  Result[3] := contentsDir + 'Resources' + PathDelim;
  Result[4] := '';
  {$ELSE}
  SetLength(Result, 3);
  Result[0] := exeDir;
  Result[1] := exeDir + 'lib' + PathDelim;
  Result[2] := '';
  {$ENDIF}
end;

function PdfiumSearchCandidates: TPdfiumStringArray;
var
  dirs, names: TPdfiumStringArray;
  d, n, count: Integer;
begin
  dirs := PdfiumCandidateDirs;
  names := PdfiumCandidateFileNames;
  SetLength(Result, Length(dirs) * Length(names));
  count := 0;
  for d := 0 to High(dirs) do
  begin
    for n := 0 to High(names) do
    begin
      Result[count] := dirs[d] + names[n];
      Inc(count);
    end;
  end;
end;

constructor EPdfiumError.Create(const AMessage: String; AErrorCode: LongWord = 0);
begin
  inherited Create(AMessage);
  FErrorCode := AErrorCode;
end;

{ TPdfiumLock }

procedure TPdfiumLock.Acquire;
begin
  inherited Acquire;
  {$IF FPC_FULLVERSION < 30203}
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  {$ENDIF}
end;

procedure BindProc(const AName: String; var AProc: Pointer);
begin
  AProc := GetProcAddress(gLibHandle, PChar(AName));
  if not Assigned(AProc) then
    raise EPdfiumError.Create('PDFium library is missing expected function: ' + AName);
end;

procedure BindOptionalProc(const AName: String; var AProc: Pointer);
begin
  AProc := GetProcAddress(gLibHandle, PChar(AName));
end;

procedure BindAllProcs;
begin
  BindProc('FPDF_InitLibrary', Pointer(FPDF_InitLibrary));
  BindProc('FPDF_DestroyLibrary', Pointer(FPDF_DestroyLibrary));
  BindProc('FPDF_GetLastError', Pointer(FPDF_GetLastError));
  BindProc('FPDF_LoadDocument', Pointer(FPDF_LoadDocument));
  BindProc('FPDF_LoadMemDocument64', Pointer(FPDF_LoadMemDocument64));
  BindProc('FPDF_LoadCustomDocument', Pointer(FPDF_LoadCustomDocument));
  BindProc('FPDF_CloseDocument', Pointer(FPDF_CloseDocument));
  BindProc('FPDF_GetDocPermissions', Pointer(FPDF_GetDocPermissions));
  BindProc('FPDF_GetSecurityHandlerRevision', Pointer(FPDF_GetSecurityHandlerRevision));
  BindProc('FPDF_GetMetaText', Pointer(FPDF_GetMetaText));
  BindProc('FPDF_GetDocUserPermissions', Pointer(FPDF_GetDocUserPermissions));
  BindProc('FPDF_GetFileVersion', Pointer(FPDF_GetFileVersion));
  BindProc('FPDF_GetPageCount', Pointer(FPDF_GetPageCount));
  BindProc('FPDF_GetPageSizeByIndexF', Pointer(FPDF_GetPageSizeByIndexF));
  BindProc('FPDF_LoadPage', Pointer(FPDF_LoadPage));
  BindProc('FPDF_ClosePage', Pointer(FPDF_ClosePage));
  BindProc('FPDF_GetPageWidthF', Pointer(FPDF_GetPageWidthF));
  BindProc('FPDF_GetPageHeightF', Pointer(FPDF_GetPageHeightF));
  BindProc('FPDFPage_GetRotation', Pointer(FPDFPage_GetRotation));
  BindProc('FPDFPage_SetRotation', Pointer(FPDFPage_SetRotation));
  BindProc('FPDFPage_HasTransparency', Pointer(FPDFPage_HasTransparency));
  BindProc('FPDF_RenderPageBitmap', Pointer(FPDF_RenderPageBitmap));
  BindProc('FPDFBitmap_CreateEx', Pointer(FPDFBitmap_CreateEx));
  BindProc('FPDFBitmap_FillRect', Pointer(FPDFBitmap_FillRect));
  BindProc('FPDFBitmap_GetBuffer', Pointer(FPDFBitmap_GetBuffer));
  BindProc('FPDFBitmap_GetFormat', Pointer(FPDFBitmap_GetFormat));
  BindProc('FPDFBitmap_GetWidth', Pointer(FPDFBitmap_GetWidth));
  BindProc('FPDFBitmap_GetHeight', Pointer(FPDFBitmap_GetHeight));
  BindProc('FPDFBitmap_GetStride', Pointer(FPDFBitmap_GetStride));
  BindProc('FPDFBitmap_Destroy', Pointer(FPDFBitmap_Destroy));

  BindProc('FPDFText_LoadPage', Pointer(FPDFText_LoadPage));
  BindProc('FPDFText_ClosePage', Pointer(FPDFText_ClosePage));
  BindProc('FPDFText_CountChars', Pointer(FPDFText_CountChars));
  BindProc('FPDFText_GetUnicode', Pointer(FPDFText_GetUnicode));
  BindProc('FPDFText_GetFontSize', Pointer(FPDFText_GetFontSize));
  BindProc('FPDFText_GetCharBox', Pointer(FPDFText_GetCharBox));
  BindProc('FPDFText_GetCharOrigin', Pointer(FPDFText_GetCharOrigin));
  BindProc('FPDFText_GetCharIndexAtPos', Pointer(FPDFText_GetCharIndexAtPos));
  BindProc('FPDFText_GetText', Pointer(FPDFText_GetText));
  BindProc('FPDFText_CountRects', Pointer(FPDFText_CountRects));
  BindProc('FPDFText_GetRect', Pointer(FPDFText_GetRect));
  BindProc('FPDFText_GetBoundedText', Pointer(FPDFText_GetBoundedText));
  BindProc('FPDFText_FindStart', Pointer(FPDFText_FindStart));
  BindProc('FPDFText_FindNext', Pointer(FPDFText_FindNext));
  BindProc('FPDFText_FindPrev', Pointer(FPDFText_FindPrev));
  BindProc('FPDFText_GetSchResultIndex', Pointer(FPDFText_GetSchResultIndex));
  BindProc('FPDFText_GetSchCount', Pointer(FPDFText_GetSchCount));
  BindProc('FPDFText_FindClose', Pointer(FPDFText_FindClose));

  BindProc('FPDFBookmark_GetFirstChild', Pointer(FPDFBookmark_GetFirstChild));
  BindProc('FPDFBookmark_GetNextSibling', Pointer(FPDFBookmark_GetNextSibling));
  BindProc('FPDFBookmark_GetTitle', Pointer(FPDFBookmark_GetTitle));
  BindProc('FPDFBookmark_GetDest', Pointer(FPDFBookmark_GetDest));
  BindProc('FPDFBookmark_GetAction', Pointer(FPDFBookmark_GetAction));
  BindProc('FPDFAction_GetType', Pointer(FPDFAction_GetType));
  BindProc('FPDFAction_GetDest', Pointer(FPDFAction_GetDest));
  BindProc('FPDFAction_GetFilePath', Pointer(FPDFAction_GetFilePath));
  BindProc('FPDFAction_GetURIPath', Pointer(FPDFAction_GetURIPath));
  BindProc('FPDFDest_GetDestPageIndex', Pointer(FPDFDest_GetDestPageIndex));
  BindProc('FPDFDest_GetLocationInPage', Pointer(FPDFDest_GetLocationInPage));
  BindProc('FPDFLink_Enumerate', Pointer(FPDFLink_Enumerate));
  BindProc('FPDFLink_GetDest', Pointer(FPDFLink_GetDest));
  BindProc('FPDFLink_GetAction', Pointer(FPDFLink_GetAction));
  BindProc('FPDFLink_GetAnnotRect', Pointer(FPDFLink_GetAnnotRect));
  BindOptionalProc('FPDFBookmark_GetColor', Pointer(FPDFBookmark_GetColor));
  BindProc('FPDF_GetFileIdentifier', Pointer(FPDF_GetFileIdentifier));
  BindProc('FPDF_GetPageLabel', Pointer(FPDF_GetPageLabel));

  BindOptionalProc('FPDFCatalog_GetLanguage', Pointer(FPDFCatalog_GetLanguage));

  BindProc('FPDF_GetFormType', Pointer(FPDF_GetFormType));

  BindProc('FPDFDoc_GetAttachmentCount', Pointer(FPDFDoc_GetAttachmentCount));
  BindProc('FPDFDoc_AddAttachment', Pointer(FPDFDoc_AddAttachment));
  BindProc('FPDFDoc_GetAttachment', Pointer(FPDFDoc_GetAttachment));
  BindProc('FPDFDoc_DeleteAttachment', Pointer(FPDFDoc_DeleteAttachment));
  BindProc('FPDFAttachment_GetName', Pointer(FPDFAttachment_GetName));
  BindProc('FPDFAttachment_HasKey', Pointer(FPDFAttachment_HasKey));
  BindProc('FPDFAttachment_GetValueType', Pointer(FPDFAttachment_GetValueType));
  BindProc('FPDFAttachment_SetStringValue', Pointer(FPDFAttachment_SetStringValue));
  BindProc('FPDFAttachment_GetStringValue', Pointer(FPDFAttachment_GetStringValue));
  BindOptionalProc('FPDFAttachment_GetSubtype', Pointer(FPDFAttachment_GetSubtype));
  BindProc('FPDFAttachment_SetFile', Pointer(FPDFAttachment_SetFile));
  BindProc('FPDFAttachment_GetFile', Pointer(FPDFAttachment_GetFile));

  BindProc('FPDF_CreateNewDocument', Pointer(FPDF_CreateNewDocument));
  BindProc('FPDF_MovePages', Pointer(FPDF_MovePages));
  BindProc('FPDFPage_CountObjects', Pointer(FPDFPage_CountObjects));
  BindProc('FPDFPage_GetObject', Pointer(FPDFPage_GetObject));
  BindProc('FPDFPageObj_GetType', Pointer(FPDFPageObj_GetType));
  BindProc('FPDFPageObj_GetBounds', Pointer(FPDFPageObj_GetBounds));
  BindProc('FPDFPageObj_GetMatrix', Pointer(FPDFPageObj_GetMatrix));
  BindProc('FPDFImageObj_GetBitmap', Pointer(FPDFImageObj_GetBitmap));
  BindProc('FPDFImageObj_GetRenderedBitmap', Pointer(FPDFImageObj_GetRenderedBitmap));
  BindProc('FPDFImageObj_GetImageMetadata', Pointer(FPDFImageObj_GetImageMetadata));
  BindProc('FPDFImageObj_GetImagePixelSize', Pointer(FPDFImageObj_GetImagePixelSize));

  BindProc('FPDFPage_Delete', Pointer(FPDFPage_Delete));
  BindProc('FPDF_ImportPages', Pointer(FPDF_ImportPages));
  BindProc('FPDF_ImportPagesByIndex', Pointer(FPDF_ImportPagesByIndex));

  BindProc('FPDF_SaveAsCopy', Pointer(FPDF_SaveAsCopy));
  BindProc('FPDF_SaveWithVersion', Pointer(FPDF_SaveWithVersion));

  BindProc('FPDF_RenderPageBitmapWithColorScheme_Start', Pointer(FPDF_RenderPageBitmapWithColorScheme_Start));
  BindProc('FPDF_RenderPage_Continue', Pointer(FPDF_RenderPage_Continue));
  BindProc('FPDF_RenderPage_Close', Pointer(FPDF_RenderPage_Close));

  BindProc('FPDFPage_GetThumbnailAsBitmap', Pointer(FPDFPage_GetThumbnailAsBitmap));

  {$IFDEF WINDOWS}
  BindOptionalProc('FPDF_RenderPage', Pointer(FPDF_RenderPage));
  {$ENDIF}
end;

procedure UnbindAllProcs;
begin
  Pointer(FPDF_InitLibrary) := nil;
  Pointer(FPDF_DestroyLibrary) := nil;
  Pointer(FPDF_GetLastError) := nil;
  Pointer(FPDF_LoadDocument) := nil;
  Pointer(FPDF_LoadMemDocument64) := nil;
  Pointer(FPDF_LoadCustomDocument) := nil;
  Pointer(FPDF_CloseDocument) := nil;
  Pointer(FPDF_GetDocPermissions) := nil;
  Pointer(FPDF_GetSecurityHandlerRevision) := nil;
  Pointer(FPDF_GetMetaText) := nil;
  Pointer(FPDF_GetDocUserPermissions) := nil;
  Pointer(FPDF_GetFileVersion) := nil;
  Pointer(FPDF_GetPageCount) := nil;
  Pointer(FPDF_GetPageSizeByIndexF) := nil;
  Pointer(FPDF_LoadPage) := nil;
  Pointer(FPDF_ClosePage) := nil;
  Pointer(FPDF_GetPageWidthF) := nil;
  Pointer(FPDF_GetPageHeightF) := nil;
  Pointer(FPDFPage_GetRotation) := nil;
  Pointer(FPDFPage_SetRotation) := nil;
  Pointer(FPDFPage_HasTransparency) := nil;
  Pointer(FPDF_RenderPageBitmap) := nil;
  Pointer(FPDFBitmap_CreateEx) := nil;
  Pointer(FPDFBitmap_FillRect) := nil;
  Pointer(FPDFBitmap_GetBuffer) := nil;
  Pointer(FPDFBitmap_GetFormat) := nil;
  Pointer(FPDFBitmap_GetWidth) := nil;
  Pointer(FPDFBitmap_GetHeight) := nil;
  Pointer(FPDFBitmap_GetStride) := nil;
  Pointer(FPDFBitmap_Destroy) := nil;

  Pointer(FPDFText_LoadPage) := nil;
  Pointer(FPDFText_ClosePage) := nil;
  Pointer(FPDFText_CountChars) := nil;
  Pointer(FPDFText_GetUnicode) := nil;
  Pointer(FPDFText_GetFontSize) := nil;
  Pointer(FPDFText_GetCharBox) := nil;
  Pointer(FPDFText_GetCharOrigin) := nil;
  Pointer(FPDFText_GetCharIndexAtPos) := nil;
  Pointer(FPDFText_GetText) := nil;
  Pointer(FPDFText_CountRects) := nil;
  Pointer(FPDFText_GetRect) := nil;
  Pointer(FPDFText_GetBoundedText) := nil;
  Pointer(FPDFText_FindStart) := nil;
  Pointer(FPDFText_FindNext) := nil;
  Pointer(FPDFText_FindPrev) := nil;
  Pointer(FPDFText_GetSchResultIndex) := nil;
  Pointer(FPDFText_GetSchCount) := nil;
  Pointer(FPDFText_FindClose) := nil;

  Pointer(FPDFBookmark_GetFirstChild) := nil;
  Pointer(FPDFBookmark_GetNextSibling) := nil;
  Pointer(FPDFBookmark_GetTitle) := nil;
  Pointer(FPDFBookmark_GetDest) := nil;
  Pointer(FPDFBookmark_GetAction) := nil;
  Pointer(FPDFAction_GetType) := nil;
  Pointer(FPDFAction_GetDest) := nil;
  Pointer(FPDFAction_GetFilePath) := nil;
  Pointer(FPDFAction_GetURIPath) := nil;
  Pointer(FPDFDest_GetDestPageIndex) := nil;
  Pointer(FPDFDest_GetLocationInPage) := nil;
  Pointer(FPDFLink_Enumerate) := nil;
  Pointer(FPDFLink_GetDest) := nil;
  Pointer(FPDFLink_GetAction) := nil;
  Pointer(FPDFLink_GetAnnotRect) := nil;
  Pointer(FPDFBookmark_GetColor) := nil;
  Pointer(FPDF_GetFileIdentifier) := nil;
  Pointer(FPDF_GetPageLabel) := nil;

  Pointer(FPDFCatalog_GetLanguage) := nil;

  Pointer(FPDF_GetFormType) := nil;

  Pointer(FPDFDoc_GetAttachmentCount) := nil;
  Pointer(FPDFDoc_AddAttachment) := nil;
  Pointer(FPDFDoc_GetAttachment) := nil;
  Pointer(FPDFDoc_DeleteAttachment) := nil;
  Pointer(FPDFAttachment_GetName) := nil;
  Pointer(FPDFAttachment_HasKey) := nil;
  Pointer(FPDFAttachment_GetValueType) := nil;
  Pointer(FPDFAttachment_SetStringValue) := nil;
  Pointer(FPDFAttachment_GetStringValue) := nil;
  Pointer(FPDFAttachment_GetSubtype) := nil;
  Pointer(FPDFAttachment_SetFile) := nil;
  Pointer(FPDFAttachment_GetFile) := nil;

  Pointer(FPDF_CreateNewDocument) := nil;
  Pointer(FPDF_MovePages) := nil;
  Pointer(FPDFPage_CountObjects) := nil;
  Pointer(FPDFPage_GetObject) := nil;
  Pointer(FPDFPageObj_GetType) := nil;
  Pointer(FPDFPageObj_GetBounds) := nil;
  Pointer(FPDFPageObj_GetMatrix) := nil;
  Pointer(FPDFImageObj_GetBitmap) := nil;
  Pointer(FPDFImageObj_GetRenderedBitmap) := nil;
  Pointer(FPDFImageObj_GetImageMetadata) := nil;
  Pointer(FPDFImageObj_GetImagePixelSize) := nil;

  Pointer(FPDFPage_Delete) := nil;
  Pointer(FPDF_ImportPages) := nil;
  Pointer(FPDF_ImportPagesByIndex) := nil;

  Pointer(FPDF_SaveAsCopy) := nil;
  Pointer(FPDF_SaveWithVersion) := nil;

  Pointer(FPDF_RenderPageBitmapWithColorScheme_Start) := nil;
  Pointer(FPDF_RenderPage_Continue) := nil;
  Pointer(FPDF_RenderPage_Close) := nil;

  Pointer(FPDFPage_GetThumbnailAsBitmap) := nil;

  {$IFDEF WINDOWS}
  Pointer(FPDF_RenderPage) := nil;
  {$ENDIF}
end;

function PdfiumRenderPageAvailable: Boolean;
begin
  {$IFDEF WINDOWS}
  Result := Assigned(FPDF_RenderPage);
  {$ELSE}
  Result := False;
  {$ENDIF}
end;

procedure PdfiumInitialize(const ALibraryPath: String = '');
var
  loadPath, tried: String;
  candidates: TPdfiumStringArray;
  i: Integer;
begin
  if gRefCount > 0 then
  begin
    Inc(gRefCount);
    exit;
  end;
  gLibHandle := NilHandle;
  if ALibraryPath <> '' then
  begin
    loadPath := ALibraryPath;
    gLibHandle := LoadLibrary(PChar(loadPath));
    if gLibHandle = NilHandle then
      raise EPdfiumError.Create('Could not load the PDFium shared library from: ' + loadPath);
  end
  else
  begin
    candidates := PdfiumSearchCandidates;
    tried := '';
    loadPath := '';
    for i := 0 to High(candidates) do
    begin
      loadPath := candidates[i];
      gLibHandle := LoadLibrary(PChar(loadPath));
      if gLibHandle <> NilHandle then
        break;
      if tried <> '' then
        tried := tried + ', ';
      if loadPath = '' then
        tried := tried + '(system search path)'
      else
        tried := tried + loadPath;
    end;
    if gLibHandle = NilHandle then
      raise EPdfiumError.Create('Could not locate the PDFium shared library automatically. Tried: ' + tried +
        '. Place the library next to the application executable, in a "lib" subfolder next to it, ' +
        'somewhere your OS searches for shared libraries, or pass an explicit path to PdfiumInitialize.');
  end;
  try
    BindAllProcs;
  except
    UnbindAllProcs;
    UnloadLibrary(gLibHandle);
    gLibHandle := NilHandle;
    raise;
  end;
  FPDF_InitLibrary();
  { PDFium expects unmasked FPU exceptions (denormals/NaN) to be ignored by
    the CPU; FPC's default unmasking crashes every render call otherwise. }
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  gLibraryPath := loadPath;
  gRefCount := 1;
end;

procedure PdfiumFinalize;
begin
  if gRefCount <= 0 then
    exit;
  Dec(gRefCount);
  if gRefCount > 0 then
    exit;
  if Assigned(FPDF_DestroyLibrary) then
    FPDF_DestroyLibrary();
  UnbindAllProcs;
  if gLibHandle <> NilHandle then
    UnloadLibrary(gLibHandle);
  gLibHandle := NilHandle;
  gLibraryPath := '';
end;

function PdfiumLoaded: Boolean;
begin
  Result := gRefCount > 0;
end;

procedure PdfiumCheckLoaded;
begin
  if not PdfiumLoaded then
    raise EPdfiumError.Create('PDFium library has not been initialised. Call PdfiumInitialize first.');
end;

procedure PdfiumEnsureInitialized;
begin
  if not PdfiumLoaded then
    PdfiumInitialize('');
end;

function PdfiumVersion: String;
{$IFDEF WINDOWS}
var
  infoSize, handleDummy: DWORD;
  buffer: array of Byte;
  fixedInfoPtr: Pointer;
  fixedInfoLen: UINT;
  fixedInfo: PVSFixedFileInfo;
{$ENDIF}
begin
  Result := '';
  if gLibraryPath = '' then
    exit;
  {$IFDEF WINDOWS}
  infoSize := GetFileVersionInfoSize(PChar(gLibraryPath), @handleDummy);
  if infoSize = 0 then
    exit;
  SetLength(buffer, infoSize);
  if not GetFileVersionInfo(PChar(gLibraryPath), 0, infoSize, @buffer[0]) then
    exit;
  if not VerQueryValue(@buffer[0], '\', fixedInfoPtr, fixedInfoLen) then
    exit;
  fixedInfo := PVSFixedFileInfo(fixedInfoPtr);
  Result := Format('%d.%d.%d.%d', [
    HiWord(fixedInfo^.dwFileVersionMS), LoWord(fixedInfo^.dwFileVersionMS),
    HiWord(fixedInfo^.dwFileVersionLS), LoWord(fixedInfo^.dwFileVersionLS)]);
  {$ENDIF}
end;

initialization
  PdfiumGlobalLock := TPdfiumLock.Create;

finalization
  while PdfiumLoaded do
    PdfiumFinalize;
  PdfiumGlobalLock.Free;

end.
