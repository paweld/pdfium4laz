unit PdfiumText;

{$mode objfpc}{$H+}{$inline on}

interface

uses
  Classes, SysUtils, Types, Math, PdfiumLib, PdfiumCore;

type
  TPdfRectFArray = array of TRectF;

  TPdfCharInfo = record
    Unicode: WideChar;
    Bounds: TRectF;
    FontSize: Double;
  end;

  TPdfTextFormat = (tfPlain, tfNatural, tfFormatted);

  TPdfTextPage = class
  private
    FOwner: TPdfPage;
    FHandle: FPDF_TEXTPAGE;
    function ExtractAllText: String;
    function ExtractTextInReadingOrder: String;
    function ExtractTextPreservingLayout: String;
    function GetChar(AIndex: Integer): TPdfCharInfo;
  public
    constructor Create(APage: TPdfPage);
    destructor Destroy; override;
    function CharCount: Integer;
    function ExtractText(AStartIndex, ACount: Integer): String;
    function ExtractTextInRect(const ARect: TRectF): String;
    function BoundsForRange(AStartIndex, ACount: Integer): TRectF;
    function CharIndexAtPos(APdfX, APdfY: Double; ATolerance: Double = 5): Integer;
    function GetCharBaselineY(AIndex: Integer): Double;
    function GetText(AFormat: TPdfTextFormat = tfPlain): String;
    property Handle: FPDF_TEXTPAGE read FHandle;
    property Page: TPdfPage read FOwner;
    property Characters[AIndex: Integer]: TPdfCharInfo read GetChar;
  end;

  TPdfSearchFlag = (sfMatchCase, sfMatchWholeWord);
  TPdfSearchFlags = set of TPdfSearchFlag;

  TPdfSearchMatch = record
    StartIndex: Integer;
    Count: Integer;
    Bounds: TRectF;
  end;

  TPdfSearch = class
  private
    FTextPage: TPdfTextPage;
    FHandle: FPDF_SCHHANDLE;
    FQuery: UnicodeString;
    FFlags: TPdfSearchFlags;
    FStartIndex: Integer;
    function BuildMatch(AStartIndex, ACount: Integer): TPdfSearchMatch;
    function RawFlags: LongWord;
  public
    { AStartIndex is the character to start from; -1 starts at the end of the page,
      so the first FindPrev returns the page's last match. }
    constructor Create(ATextPage: TPdfTextPage; const AQuery: String; AFlags: TPdfSearchFlags = [];
      AStartIndex: Integer = 0);
    destructor Destroy; override;
    function FindNext(out AMatch: TPdfSearchMatch): Boolean;
    function FindPrev(out AMatch: TPdfSearchMatch): Boolean;
    procedure Reset;
  end;

  TPdfSelection = class
  private
    FTextPage: TPdfTextPage;
    FStartIndex: Integer;
    FCount: Integer;
  public
    constructor Create(ATextPage: TPdfTextPage);
    procedure SelectRange(AStartIndex, ACount: Integer);
    procedure SelectWord(ACharIndex: Integer);
    procedure SelectLine(ACharIndex: Integer);
    procedure Clear;
    function SelectedText: String;
    function SelectionBounds: TPdfRectFArray;
    function IsEmpty: Boolean;
    property StartIndex: Integer read FStartIndex;
    property Count: Integer read FCount;
  end;

function PdfGetText(APage: TPdfPage; AFormat: TPdfTextFormat = tfPlain): String;

implementation

function IsWordBreakChar(AUnicode: WideChar): Boolean; inline;
begin
  Result := (AUnicode = ' ') or (AUnicode = #9) or (AUnicode = #10) or (AUnicode = #13);
end;

function IsLineBreakChar(AUnicode: WideChar): Boolean; inline;
begin
  Result := (AUnicode = #10) or (AUnicode = #13);
end;

{ TPdfTextPage }

constructor TPdfTextPage.Create(APage: TPdfPage);
begin
  inherited Create;
  FOwner := APage;
  FOwner.Document.Lock.Enter;
  try
    FHandle := FPDFText_LoadPage(APage.Handle);
  finally
    FOwner.Document.Lock.Leave;
  end;
  if FHandle = nil then
    raise EPdfiumError.Create('Could not load the text page.');
end;

destructor TPdfTextPage.Destroy;
begin
  if FHandle <> nil then
  begin
    FOwner.Document.Lock.Enter;
    try
      FPDFText_ClosePage(FHandle);
    finally
      FOwner.Document.Lock.Leave;
    end;
  end;
  inherited Destroy;
end;

function TPdfTextPage.CharCount: Integer;
begin
  FOwner.Document.Lock.Enter;
  try
    Result := FPDFText_CountChars(FHandle);
  finally
    FOwner.Document.Lock.Leave;
  end;
end;

function TPdfTextPage.GetChar(AIndex: Integer): TPdfCharInfo;
var
  l, r, b, t: Double;
begin
  FOwner.Document.Lock.Enter;
  try
    if (AIndex < 0) or (AIndex >= FPDFText_CountChars(FHandle)) then
      raise EPdfiumError.Create(Format('Characters[]: character index %d is out of range (0..%d).', [AIndex, FPDFText_CountChars(FHandle) - 1]));
    Result.Unicode := WideChar(FPDFText_GetUnicode(FHandle, AIndex));
    FPDFText_GetCharBox(FHandle, AIndex, l, r, b, t);
    Result.Bounds.Left := l;
    Result.Bounds.Right := r;
    Result.Bounds.Bottom := b;
    Result.Bounds.Top := t;
    Result.FontSize := FPDFText_GetFontSize(FHandle, AIndex);
  finally
    FOwner.Document.Lock.Leave;
  end;
end;

function TPdfTextPage.ExtractText(AStartIndex, ACount: Integer): String;
var
  buffer: array of WideChar;
begin
  Result := '';
  if ACount <= 0 then
    exit;
  SetLength(buffer, ACount + 1);
  FOwner.Document.Lock.Enter;
  try
    FPDFText_GetText(FHandle, AStartIndex, ACount, @buffer[0]);
  finally
    FOwner.Document.Lock.Leave;
  end;
  Result := PWideChar(@buffer[0]);
end;

function TPdfTextPage.ExtractAllText: String;
begin
  Result := ExtractText(0, CharCount);
end;

{ FPDFText_GetBoundedText may include one trailing whitespace character right
  at the rectangle's edge - trim the result if that matters to the caller. }
function TPdfTextPage.ExtractTextInRect(const ARect: TRectF): String;
var
  neededChars: Integer;
  buffer: array of WideChar;
begin
  Result := '';
  FOwner.Document.Lock.Enter;
  try
    neededChars := FPDFText_GetBoundedText(FHandle, ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, nil, 0);
    if neededChars <= 0 then
      exit;
    SetLength(buffer, neededChars + 1);
    FPDFText_GetBoundedText(FHandle, ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, @buffer[0], neededChars);
  finally
    FOwner.Document.Lock.Leave;
  end;
  Result := PWideChar(@buffer[0]);
end;

function TPdfTextPage.GetText(AFormat: TPdfTextFormat = tfPlain): String;
begin
  case AFormat of
    tfNatural: Result := ExtractTextInReadingOrder;
    tfFormatted: Result := ExtractTextPreservingLayout;
  else
    Result := ExtractAllText;
  end;
end;

function TPdfTextPage.CharIndexAtPos(APdfX, APdfY: Double; ATolerance: Double = 5): Integer;
begin
  FOwner.Document.Lock.Enter;
  try
    Result := FPDFText_GetCharIndexAtPos(FHandle, APdfX, APdfY, ATolerance, ATolerance);
  finally
    FOwner.Document.Lock.Leave;
  end;
end;

function TPdfTextPage.GetCharBaselineY(AIndex: Integer): Double;
var
  x: Double;
begin
  FOwner.Document.Lock.Enter;
  try
    if FPDFText_GetCharOrigin(FHandle, AIndex, x, Result) = 0 then
      Result := 0;
  finally
    FOwner.Document.Lock.Leave;
  end;
end;

type
  TPdfLayoutChar = record
    Unicode: WideChar;
    Left, Right, BaselineY, FontSize: Double;
    OrigIndex: Integer;
    HadSpaceBefore: Boolean;
  end;
  TPdfLayoutCharArray = array of TPdfLayoutChar;

  TPdfLayoutLine = record
    FirstChar, LastChar: Integer; // inclusive range into a TPdfLayoutCharArray
    BaselineY: Double;
    AvgFontSize: Double;
  end;
  TPdfLayoutLineArray = array of TPdfLayoutLine;

procedure QuickSortByBaselineYDesc(var A: TPdfLayoutCharArray; ALo, AHi: Integer);
var
  i, j: Integer;
  pivot: Double;
  tmp: TPdfLayoutChar;
begin
  if ALo >= AHi then
    exit;
  i := ALo;
  j := AHi;
  pivot := A[(ALo + AHi) div 2].BaselineY;
  repeat
    while A[i].BaselineY > pivot do
      Inc(i);
    while A[j].BaselineY < pivot do
      Dec(j);
    if i <= j then
    begin
      tmp := A[i];
      A[i] := A[j];
      A[j] := tmp;
      Inc(i);
      Dec(j);
    end;
  until i > j;
  if ALo < j then
    QuickSortByBaselineYDesc(A, ALo, j);
  if i < AHi then
    QuickSortByBaselineYDesc(A, i, AHi);
end;

procedure InsertionSortByLeftAsc(var A: TPdfLayoutCharArray; ALo, AHi: Integer);
var
  i, j: Integer;
  tmp: TPdfLayoutChar;
begin
  for i := ALo + 1 to AHi do
  begin
    tmp := A[i];
    j := i;
    while (j > ALo) and (A[j - 1].Left > tmp.Left) do
    begin
      A[j] := A[j - 1];
      Dec(j);
    end;
    A[j] := tmp;
  end;
end;

procedure BuildLayoutLines(ATextPage: TPdfTextPage; out AChars: TPdfLayoutCharArray; out ALines: TPdfLayoutLineArray);
var
  n, i, j, lineStart: Integer;
  ci: TPdfCharInfo;
  tolerance, sizeSum: Double;
  pendingSpace: Boolean;
begin
  SetLength(AChars, ATextPage.CharCount);
  n := 0;
  pendingSpace := False;
  for i := 0 to ATextPage.CharCount - 1 do
  begin
    ci := ATextPage.Characters[i];
    if (ci.Bounds.Right <= ci.Bounds.Left) and (ci.Bounds.Top <= ci.Bounds.Bottom) then
    begin
      pendingSpace := True;
      continue;
    end;
    AChars[n].Unicode := ci.Unicode;
    AChars[n].Left := ci.Bounds.Left;
    AChars[n].Right := ci.Bounds.Right;
    AChars[n].FontSize := ci.FontSize;
    AChars[n].BaselineY := ATextPage.GetCharBaselineY(i);
    AChars[n].OrigIndex := n;
    AChars[n].HadSpaceBefore := pendingSpace;
    pendingSpace := False;
    Inc(n);
  end;
  SetLength(AChars, n);
  SetLength(ALines, 0);
  if n = 0 then
    exit;

  QuickSortByBaselineYDesc(AChars, 0, n - 1);

  lineStart := 0;
  for i := 1 to n do
  begin
    if i < n then
    begin
      tolerance := 0.35 * Min(AChars[lineStart].FontSize, AChars[i].FontSize);
      if tolerance < 1.0 then
        tolerance := 1.0;
    end;
    if (i = n) or (Abs(AChars[i].BaselineY - AChars[lineStart].BaselineY) > tolerance) then
    begin
      InsertionSortByLeftAsc(AChars, lineStart, i - 1);
      sizeSum := 0;
      for j := lineStart to i - 1 do
        sizeSum := sizeSum + AChars[j].FontSize;
      SetLength(ALines, Length(ALines) + 1);
      ALines[High(ALines)].FirstChar := lineStart;
      ALines[High(ALines)].LastChar := i - 1;
      ALines[High(ALines)].BaselineY := AChars[lineStart].BaselineY;
      ALines[High(ALines)].AvgFontSize := sizeSum / (i - lineStart);
      lineStart := i;
    end;
  end;
end;

function IsParagraphBreak(const ALines: TPdfLayoutLineArray; AIndex: Integer): Boolean;
var
  typicalGap: Double;
begin
  if ALines[AIndex - 1].AvgFontSize < ALines[AIndex].AvgFontSize then
    typicalGap := 2.0 * ALines[AIndex - 1].AvgFontSize
  else
    typicalGap := 2.0 * ALines[AIndex].AvgFontSize;
  Result := (ALines[AIndex - 1].BaselineY - ALines[AIndex].BaselineY) > typicalGap;
end;

function SpaceCountBetween(const AChars: TPdfLayoutCharArray; APrev, ACur: Integer; ASpaceWidth: Double): Integer;
var
  gap: Double;
begin
  // Stream-adjacent chars: trust HadSpaceBefore, not the ink-box gap.
  if AChars[ACur].OrigIndex = AChars[APrev].OrigIndex + 1 then
  begin
    if AChars[ACur].HadSpaceBefore then
      Result := 1
    else
      Result := 0;
    exit;
  end;
  gap := AChars[ACur].Left - AChars[APrev].Right;
  if gap <= ASpaceWidth * 0.6 then
    Result := 0
  else
  begin
    Result := Round(gap / ASpaceWidth);
    if Result < 1 then
      Result := 1;
  end;
end;

function TPdfTextPage.ExtractTextInReadingOrder: String;
var
  chars: TPdfLayoutCharArray;
  lines: TPdfLayoutLineArray;
  lineIdx, i: Integer;
  lineText: UnicodeString;
  full: UnicodeString;
  spaceWidth: Double;
begin
  BuildLayoutLines(Self, chars, lines);
  full := '';
  for lineIdx := 0 to High(lines) do
  begin
    spaceWidth := lines[lineIdx].AvgFontSize * 0.28;
    if spaceWidth <= 0 then
      spaceWidth := 1;
    lineText := '';
    for i := lines[lineIdx].FirstChar to lines[lineIdx].LastChar do
    begin
      if (i > lines[lineIdx].FirstChar) and (SpaceCountBetween(chars, i - 1, i, spaceWidth) > 0) then
        lineText := lineText + ' ';
      lineText := lineText + chars[i].Unicode;
    end;
    if full <> '' then
      full := full + UnicodeString(LineEnding);
    if (lineIdx > 0) and IsParagraphBreak(lines, lineIdx) then
      full := full + UnicodeString(LineEnding);
    full := full + lineText;
  end;
  Result := full;
end;

function TPdfTextPage.ExtractTextPreservingLayout: String;
var
  chars: TPdfLayoutCharArray;
  lines: TPdfLayoutLineArray;
  lineIdx, i, leadingSpaces, gapSpaces: Integer;
  lineText: UnicodeString;
  full: UnicodeString;
  spaceWidth, minLeft: Double;
begin
  BuildLayoutLines(Self, chars, lines);
  full := '';
  if Length(chars) = 0 then
  begin
    Result := full;
    exit;
  end;
  minLeft := chars[0].Left;
  for i := 1 to High(chars) do
  begin
    if chars[i].Left < minLeft then
      minLeft := chars[i].Left;
  end;

  for lineIdx := 0 to High(lines) do
  begin
    spaceWidth := lines[lineIdx].AvgFontSize * 0.28;
    if spaceWidth <= 0 then
      spaceWidth := 1;
    leadingSpaces := Round((chars[lines[lineIdx].FirstChar].Left - minLeft) / spaceWidth);
    if leadingSpaces < 0 then
      leadingSpaces := 0;
    lineText := UnicodeString(StringOfChar(' ', leadingSpaces));
    for i := lines[lineIdx].FirstChar to lines[lineIdx].LastChar do
    begin
      if i > lines[lineIdx].FirstChar then
      begin
        gapSpaces := SpaceCountBetween(chars, i - 1, i, spaceWidth);
        if gapSpaces > 0 then
          lineText := lineText + UnicodeString(StringOfChar(' ', gapSpaces));
      end;
      lineText := lineText + chars[i].Unicode;
    end;
    if full <> '' then
      full := full + UnicodeString(LineEnding);
    if (lineIdx > 0) and IsParagraphBreak(lines, lineIdx) then
      full := full + UnicodeString(LineEnding);
    full := full + lineText;
  end;
  Result := full;
end;

function TPdfTextPage.BoundsForRange(AStartIndex, ACount: Integer): TRectF;
var
  rectCount, i: Integer;
  l, t, r, b: Double;
  first: Boolean;
begin
  FillChar(Result, SizeOf(Result), 0);
  FOwner.Document.Lock.Enter;
  try
    rectCount := FPDFText_CountRects(FHandle, AStartIndex, ACount);
    first := True;
    for i := 0 to rectCount - 1 do
    begin
      FPDFText_GetRect(FHandle, i, l, t, r, b);
      if first then
      begin
        Result.Left := l;
        Result.Top := t;
        Result.Right := r;
        Result.Bottom := b;
        first := False;
      end
      else
      begin
        if l < Result.Left then
          Result.Left := l;
        if r > Result.Right then
          Result.Right := r;
        { PDF page space is Y-up: the topmost edge has the largest Y. }
        if t > Result.Top then
          Result.Top := t;
        if b < Result.Bottom then
          Result.Bottom := b;
      end;
    end;
  finally
    FOwner.Document.Lock.Leave;
  end;
end;

{ TPdfSearch }

function TPdfSearch.RawFlags: LongWord;
begin
  Result := 0;
  if sfMatchCase in FFlags then
    Result := Result or FPDF_MATCHCASE;
  if sfMatchWholeWord in FFlags then
    Result := Result or FPDF_MATCHWHOLEWORD;
end;

constructor TPdfSearch.Create(ATextPage: TPdfTextPage; const AQuery: String; AFlags: TPdfSearchFlags = [];
  AStartIndex: Integer = 0);
begin
  inherited Create;
  FTextPage := ATextPage;
  FQuery := UnicodeString(AQuery);
  FFlags := AFlags;
  FStartIndex := AStartIndex;
  FTextPage.Page.Document.Lock.Enter;
  try
    FHandle := FPDFText_FindStart(FTextPage.Handle, PWideChar(FQuery), RawFlags, FStartIndex);
  finally
    FTextPage.Page.Document.Lock.Leave;
  end;
  if FHandle = nil then
    raise EPdfiumError.Create('TPdfSearch: FPDFText_FindStart failed.');
end;

destructor TPdfSearch.Destroy;
begin
  if FHandle <> nil then
  begin
    FTextPage.Page.Document.Lock.Enter;
    try
      FPDFText_FindClose(FHandle);
    finally
      FTextPage.Page.Document.Lock.Leave;
    end;
  end;
  inherited Destroy;
end;

function TPdfSearch.BuildMatch(AStartIndex, ACount: Integer): TPdfSearchMatch;
begin
  Result.StartIndex := AStartIndex;
  Result.Count := ACount;
  Result.Bounds := FTextPage.BoundsForRange(AStartIndex, ACount);
end;

function TPdfSearch.FindNext(out AMatch: TPdfSearchMatch): Boolean;
var
  idx, cnt: Integer;
begin
  FTextPage.Page.Document.Lock.Enter;
  try
    Result := FPDFText_FindNext(FHandle) <> 0;
    if Result then
    begin
      idx := FPDFText_GetSchResultIndex(FHandle);
      cnt := FPDFText_GetSchCount(FHandle);
    end;
  finally
    FTextPage.Page.Document.Lock.Leave;
  end;
  if Result then
    AMatch := BuildMatch(idx, cnt)
  else
    FillChar(AMatch, SizeOf(AMatch), 0);
end;

function TPdfSearch.FindPrev(out AMatch: TPdfSearchMatch): Boolean;
var
  idx, cnt: Integer;
begin
  FTextPage.Page.Document.Lock.Enter;
  try
    Result := FPDFText_FindPrev(FHandle) <> 0;
    if Result then
    begin
      idx := FPDFText_GetSchResultIndex(FHandle);
      cnt := FPDFText_GetSchCount(FHandle);
    end;
  finally
    FTextPage.Page.Document.Lock.Leave;
  end;
  if Result then
    AMatch := BuildMatch(idx, cnt)
  else
    FillChar(AMatch, SizeOf(AMatch), 0);
end;

procedure TPdfSearch.Reset;
begin
  FTextPage.Page.Document.Lock.Enter;
  try
    if FHandle <> nil then
      FPDFText_FindClose(FHandle);
    FHandle := FPDFText_FindStart(FTextPage.Handle, PWideChar(FQuery), RawFlags, FStartIndex);
  finally
    FTextPage.Page.Document.Lock.Leave;
  end;
end;

{ TPdfSelection }

constructor TPdfSelection.Create(ATextPage: TPdfTextPage);
begin
  inherited Create;
  FTextPage := ATextPage;
  FStartIndex := -1;
  FCount := 0;
end;

procedure TPdfSelection.SelectRange(AStartIndex, ACount: Integer);
begin
  FStartIndex := AStartIndex;
  FCount := ACount;
end;

procedure TPdfSelection.SelectWord(ACharIndex: Integer);
var
  leftIdx, rightIdx, total: Integer;
begin
  total := FTextPage.CharCount;
  if (ACharIndex < 0) or (ACharIndex >= total) or IsWordBreakChar(FTextPage.Characters[ACharIndex].Unicode) then
  begin
    Clear;
    exit;
  end;
  leftIdx := ACharIndex;
  while (leftIdx > 0) and not IsWordBreakChar(FTextPage.Characters[leftIdx - 1].Unicode) do
    Dec(leftIdx);
  rightIdx := ACharIndex;
  while (rightIdx < total - 1) and not IsWordBreakChar(FTextPage.Characters[rightIdx + 1].Unicode) do
    Inc(rightIdx);
  SelectRange(leftIdx, rightIdx - leftIdx + 1);
end;

procedure TPdfSelection.SelectLine(ACharIndex: Integer);
var
  leftIdx, rightIdx, total: Integer;
begin
  total := FTextPage.CharCount;
  if (ACharIndex < 0) or (ACharIndex >= total) then
  begin
    Clear;
    exit;
  end;
  leftIdx := ACharIndex;
  while (leftIdx > 0) and not IsLineBreakChar(FTextPage.Characters[leftIdx - 1].Unicode) do
    Dec(leftIdx);
  rightIdx := ACharIndex;
  while (rightIdx < total - 1) and not IsLineBreakChar(FTextPage.Characters[rightIdx + 1].Unicode) do
    Inc(rightIdx);
  SelectRange(leftIdx, rightIdx - leftIdx + 1);
end;

procedure TPdfSelection.Clear;
begin
  FStartIndex := -1;
  FCount := 0;
end;

function TPdfSelection.SelectedText: String;
begin
  if IsEmpty then
    Result := ''
  else
    Result := FTextPage.ExtractText(FStartIndex, FCount);
end;

function TPdfSelection.SelectionBounds: TPdfRectFArray;
var
  rectCount, i: Integer;
  l, t, r, b: Double;
begin
  if IsEmpty then
    exit;
  FTextPage.Page.Document.Lock.Enter;
  try
    rectCount := FPDFText_CountRects(FTextPage.Handle, FStartIndex, FCount);
    SetLength(Result, rectCount);
    for i := 0 to rectCount - 1 do
    begin
      FPDFText_GetRect(FTextPage.Handle, i, l, t, r, b);
      Result[i].Left := l;
      Result[i].Top := t;
      Result[i].Right := r;
      Result[i].Bottom := b;
    end;
  finally
    FTextPage.Page.Document.Lock.Leave;
  end;
end;

function TPdfSelection.IsEmpty: Boolean;
begin
  Result := (FStartIndex < 0) or (FCount <= 0);
end;

function PdfGetText(APage: TPdfPage; AFormat: TPdfTextFormat = tfPlain): String;
var
  tp: TPdfTextPage;
begin
  tp := TPdfTextPage.Create(APage);
  try
    Result := tp.GetText(AFormat);
  finally
    tp.Free;
  end;
end;

end.
