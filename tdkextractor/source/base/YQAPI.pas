unit YQAPI;

interface

uses
    SysUtils, Classes, Windows, RegExpr;

const
    FIDX_LAST = 2147483647;
    cDeltaSize = 1.5;

type
    TBMJumpTable = array[0..255] of Integer;

    TFastPosProc = function(const aSource, aFind: Pointer; const aSourceLen, aFindLen: Integer; var JumpTable: TBMJumpTable): Pointer;

function HtmlToGbk(html: string): string;

function NCPos(sub, source: string): integer;

function FieldCount(const strRecord, strFs: string): integer;

function StrCount(Sub, S: string): Integer;

function FieldValue(strSplit: string; str: string; iField: integer; cs: Boolean = False): string;

function FastPosNoCase(const aSourceString, aFindString: string; const aSourceLen, aFindLen, StartPos: Integer): Integer;

function GetFieldValueByName(RecordStr, FieldName: string; From: Integer = 1; Surround: string = '<>'): string;

procedure MakeBMTable(Buffer: PChar; BufferLen: Integer; var JumpTable: TBMJumpTable);

procedure MakeBMTableNoCase(Buffer: PChar; BufferLen: Integer; var JumpTable: TBMJumpTable);

function BMPos(const aSource, aFind: Pointer; const aSourceLen, aFindLen: Integer; var JumpTable: TBMJumpTable): Pointer;

function BMPosNoCase(const aSource, aFind: Pointer; const aSourceLen, aFindLen: Integer; var JumpTable: TBMJumpTable): Pointer;

function SmartPos(const SearchStr, SourceStr: string; const CaseSensitive: Boolean = TRUE; const StartPos: Integer = 1; const ForwardSearch: Boolean = TRUE): Integer;

function FastPos(const aSourceString, aFindString: string; const aSourceLen, aFindLen, StartPos: Integer): Integer;

function FastPosBack(const aSourceString, aFindString: string; const aSourceLen, aFindLen, StartPos: Integer): Integer;

function FastPosBackNoCase(const aSourceString, aFindString: string; const aSourceLen, aFindLen, StartPos: Integer): Integer;

function FastReplace(const aSourceString: string; const aFindString, aReplaceString: string; CaseSensitive: Boolean = False): string;

procedure FastCharMove(const Source; var Dest; Count: Integer);


//ÕýÔòÌáÈ¡º¯Êý
function GetMatch(strText: string; strExp: string; idx: integer = 0; bMS: Boolean = true; bMG: Boolean = false; bMR: Boolean = false): string;

function GetMatchsEx(strText: string; strExp: string; Matchs: TStrings = nil; bMS: Boolean = false; bMG: Boolean = false; bMR: Boolean = false; bmI: Boolean = False; iContent: integer = -1): Integer;

function GetMatchs_V3(strText: string; strExp: string; Matchs: TStrings = nil; bMS: Boolean = false; bMG: Boolean = false; bMR: Boolean = false; iContent: integer = 0): integer;

var
    GUpcaseTable: array[0..255] of char;
    GUpcaseLUT: Pointer;
    I: Integer;

implementation

procedure FastCharMove(const Source; var Dest; Count: Integer);
asm
//Note:  When this function is called, delphi passes the parameters as follows
//ECX = Count
//EAX = Const Source
//EDX = Var Dest

    //If no bytes to copy, just quit altogether, no point pushing registers
        cmp     ECX, 0
        Je      @JustQuit
    //Preserve the critical delphi registers
        push    ESI
        push    EDI
    //move Source into ESI  (generally the SOURCE register)
    //move Dest into EDI (generally the DEST register for string commands)
    //This may not actually be neccessary, as I am not using MOVsb etc
    //I may be able just to use EAX and EDX, there may be a penalty for
    //not using ESI, EDI but I doubt it, this is another thing worth trying !
        mov     ESI, EAX
        mov     EDI, EDX
    //The following loop is the same as repNZ MovSB, but oddly quicker !
@Loop:
    //Get the source byte
        Mov     AL, [ESI]
    //Point to next byte
        Inc     ESI
    //Put it into the Dest
        mov     [EDI], AL
    //Point dest to next position
        Inc     EDI
    //Dec ECX to note how many we have left to copy
        Dec     ECX
    //If ECX <> 0 then loop
        Jnz     @Loop
    //Another optimization note.
    //Many people like to do this
    //Mov AL, [ESI]
    //Mov [EDI], Al
    //Inc ESI
    //Inc ESI
    //There is a hidden problem here, I wont go into too much detail, but
    //the pentium can continue processing instructions while it is still
    //working out the result of INC ESI or INC EDI
    //(almost like a multithreaded CPU)
    //if, however, you go to use them while they are still being calculated
    //the processor will stop until they are calculated (a penalty)
    //Therefore I alter ESI and EDI as far in advance as possible of using them
    //Pop the critical Delphi registers that we have altered
        pop     EDI
        pop     ESI

@JustQuit:
end;

function FastReplace(const aSourceString: string; const aFindString, aReplaceString: string; CaseSensitive: Boolean = False): string;
var
    PResult: PChar;
    PReplace: PChar;
    PSource: PChar;
    PFind: PChar;
    PPosition: PChar;
    CurrentPos, BytesUsed, lResult, lReplace, lSource, lFind: Integer;
    Find: TFastPosProc;
    CopySize: Integer;
    JumpTable: TBMJumpTable;
begin
    LSource := Length(aSourceString);
    if LSource = 0 then
    begin
        Result := aSourceString;
        exit;
    end;
    PSource := @aSourceString[1];

    LFind := Length(aFindString);
    if LFind = 0 then
    begin
        result := aSourceString;
        exit;
    end;
    PFind := @aFindString[1];

    LReplace := Length(aReplaceString);

  //Here we may get an Integer Overflow, or OutOfMemory, if so, we use a Delta
    try
        if LReplace <= LFind then
            SetLength(Result, lSource)
        else
            SetLength(Result, (LSource * LReplace) div LFind);
    except
        SetLength(Result, 0);
    end;

    LResult := Length(Result);
    if LResult = 0 then
    begin
        LResult := Trunc((LSource + LReplace) * cDeltaSize);
        SetLength(Result, LResult);
    end;

    PResult := @Result[1];

    if CaseSensitive then
    begin
        MakeBMTable(PChar(AFindString), lFind, JumpTable);
        Find := BMPos;
    end
    else
    begin
        MakeBMTableNoCase(PChar(AFindString), lFind, JumpTable);
        Find := BMPosNoCase;
    end;

    BytesUsed := 0;
    if LReplace > 0 then
    begin
        PReplace := @aReplaceString[1];
        repeat
            PPosition := Find(PSource, PFind, lSource, lFind, JumpTable);
            if PPosition = nil then
                break;

            CopySize := PPosition - PSource;
            Inc(BytesUsed, CopySize + LReplace);

            if BytesUsed >= LResult then
            begin
    //We have run out of space
                CurrentPos := Integer(PResult) - Integer(@Result[1]) + 1;
                LResult := Trunc(LResult * cDeltaSize);
                SetLength(Result, LResult);
                PResult := @Result[CurrentPos];
            end;

            FastCharMove(PSource^, PResult^, CopySize);
            Dec(lSource, CopySize + LFind);
            Inc(PSource, CopySize + LFind);
            Inc(PResult, CopySize);

            FastCharMove(PReplace^, PResult^, LReplace);
            Inc(PResult, LReplace);

        until lSource < lFind;
    end
    else
    begin
        repeat
            PPosition := Find(PSource, PFind, lSource, lFind, JumpTable);
            if PPosition = nil then
                break;

            CopySize := PPosition - PSource;
            FastCharMove(PSource^, PResult^, CopySize);
            Dec(lSource, CopySize + LFind);
            Inc(PSource, CopySize + LFind);
            Inc(PResult, CopySize);
            Inc(BytesUsed, CopySize);
        until lSource < lFind;
    end;

    SetLength(Result, (PResult + LSource) - @Result[1]);
    if LSource > 0 then
        FastCharMove(PSource^, Result[BytesUsed + 1], LSource);
end;

function GetMatch(strText: string; strExp: string; idx: integer = 0;    //0±íÊ¾
    bMS: Boolean = true; bMG: Boolean = false; bMR: Boolean = false): string;
var
    i, nums: integer;
    RegExpr: TRegExpr;
    strLine, strContent: string;
begin
    result := '';
    if strExp = '' then
        exit;

    RegExpr := TRegExpr.Create;
    RegExpr.ModifierS := bMS;
    RegExpr.ModifierG := bMG;
    RegExpr.ModifierR := bMR;
    RegExpr.ModifierI := true; //²»Çø·Ö´óÐ¡Ð´
    RegExpr.Expression := strExp;

    RegExpr.Expression := strExp;
    if RegExpr.Exec(strText) then
    begin
        if idx > RegExpr.SubExprMatchCount then
            idx := 0;
        result := RegExpr.Match[idx];
    end;

    RegExpr.Free;
end;

function GetMatchs(strText: string; strExp: string; Matchs: TStrings = nil; bMS: Boolean = true; bMG: Boolean = false; bMR: Boolean = false; Ver: byte = 1; iContent: integer = 0): integer;

    //2014-11-24 17:05 TIGER Èç¹ûÊ¹ÓÃwidestring, ÖÐÓ¢ÎÄ¼ÆËã»á´íÎó...ÔÝÊ±ÎÞ½â
    //function GetMatchContent(strText: widestring; iContent, iMatchPos: integer): string;
    function GetMatchContent(strText: string; iContent, iMatchPos: integer; var line: integer): string;
    var
        v: string;
        istart, iend: integer;
    begin
        istart := iMatchPos - (iContent div 2);
        if istart < 1 then
            istart := 1;

        //iend:= iMatchPos+(iContent div 2);
        //if iend>length(strText) then iend:=length(strText);

        result := copy(strText, istart, iContent);

        //2014-11-24 17:14 TIGER Êä³öËùÔÚÐÐ
        v := copy(strText, 1, istart);
        line := StrCount(#13#10, v);

        {
        result:= '';
        if iContent<length(strMatch) then exit;

        ipos:= pos(strMatch, strText);
        if ipos<1 then exit;
        istart:= ipos-(iContent div 2);
        if istart<1 then istart:=1;

        iend:= ipos+(iContent div 2);
        if iend>length(strText) then iend:=length(strText);

        result:= copy(strText, istart, iend-istart);
        }
    end;

var
    RegExpr: TRegExpr;
    i, nums, line: integer;
    sline, cont: string;
    DataStrs: TStrings;
begin
    result := 0;
    if strExp = '' then
        exit;

    RegExpr := TRegExpr.Create;
    DataStrs := TStringList.Create;
    try
        with RegExpr do
        begin
            ModifierS := bMS;
            ModifierG := bMG;
            ModifierR := bMR;
            ModifierI := true; //²»Çø·Ö´óÐ¡Ð´
            Expression := strExp;

            if Exec(strText) then
            begin
                repeat
                    sline := '';

                    if (Ver = 2) or (Ver = 3) then
                    begin
                        nums := 0;
                        if Ver = 2 then
                            nums := RegExpr.SubExprMatchCount;

                        cont := '';
                        line := -1;
                        for i := 0 to nums do
                        begin
                            if iContent > 0 then
                            begin
                                cont := GetMatchContent(strText, iContent, RegExpr.MatchPos[i], line);
                                cont := FastReplace(cont, #13#10, '', false);
                                cont := FastReplace(cont, #09, '', false);
                            end;

                            sline := sline + '<line>' + inttostr(line) + '</line>' + '<match>' + RegExpr.Match[i] + '</match>' + '<content>' + cont + '</content>' + #09
                        end;
                    end
                    else
                    begin
                        sline := RegExpr.Match[iContent];
                    end;
                    Inc(result);
                    DataStrs.Add(sline);
                until not ExecNext;
                if Assigned(Matchs) then
                    Matchs.Assign(DataStrs);
            end;
        end;
    finally
        RegExpr.Free;
        DataStrs.Free;
    end;
end;



//¸ù¾Ý¸øÒÔµÄÌõ¼þ±í´ïÊ½½øÐÐ²éÕÒ²¢Êä³ö½á¹û, ÒÔÖÆ±í·û¸ô¿ª
//MatchsÔÊÐíÎªnil
//·µ»ØÆ¥Åä¸öÊý
//2008-12-08 ÐÞÕý»òÕß¸Ä½øÒ»¸ö´íÎó, ÎªºÍÒÔÇ°µÄ´úÂë±£³Ö¼æÈÝ, Ôö¼Ó°æ±¾ºÅ
//2008-12-16 Ôö¼ÓiContent²ÎÊý, ±íÊ¾Êä³öÉÏÏÂÎÄ
function GetMatchsEx(strText: string; strExp: string; Matchs: TStrings = nil; bMS: Boolean = false; bMG: Boolean = false; bMR: Boolean = false; bmI: Boolean = False; iContent: integer = -1): Integer;
var
    i, nums: integer;
    RegExpr: TRegExpr;
    strLine, strContent: string;
begin
    Result := 0;
    if strExp = '' then
        exit;

    RegExpr := TRegExpr.Create;
    try
        with RegExpr do
        begin
            ModifierS := bMS;
            ModifierG := bMG;
            ModifierR := bMR;
            ModifierI := bmI;
            Expression := strExp;

            if Exec(strText) then
            begin
                //Éú³ÉÁÐÊý¾Ý
                repeat
                    if (iContent <> -1) and Assigned(Matchs) then
                        Matchs.Add(Match[iContent])
                    else
                    begin
                        strLine := '';
                        for I := 0 to SubExprMatchCount do
                            strLine := strLine + Match[I] + #9;
                        if Assigned(Matchs) then
                            Matchs.Add(strLine);
                    end;
                    Inc(Result);
                until not ExecNext;
            end;
        end;
    finally
        RegExpr.Free;
    end;
end;

function GetMatchs_V3(strText: string; strExp: string; Matchs: TStrings = nil; bMS: Boolean = false; bMG: Boolean = false; bMR: Boolean = false; iContent: integer = 0): integer;
begin
    result := GetMatchs(strText, strExp, Matchs, bMS, bMG, bMR, 3, 0);
end;

//StartPos: ´Ó1¿ªÊ¼
function FastPosNoCase(const aSourceString, aFindString: string; const aSourceLen, aFindLen, StartPos: Integer): Integer;
var
    JumpTable: TBMJumpTable;
begin
    //If this assert failed, it is because you passed 0 for StartPos, lowest value is 1 !!
    Assert(StartPos > 0);
    if aFindLen < 1 then
    begin
        Result := 0;
        exit;
    end;
    if aFindLen > aSourceLen then
    begin
        Result := 0;
        exit;
    end;

    MakeBMTableNoCase(PChar(AFindString), aFindLen, JumpTable);
    Result := Integer(BMPosNoCase(PChar(aSourceString) + (StartPos - 1), PChar(aFindString), aSourceLen - (StartPos - 1), aFindLen, JumpTable));
    if Result > 0 then
        Result := Result - Integer(@aSourceString[1]) + 1;
end;

procedure MakeBMTableNoCase(Buffer: PChar; BufferLen: Integer; var JumpTable: TBMJumpTable);
begin
    if BufferLen = 0 then
        raise Exception.Create('BufferLen is 0');
    asm
        push    EDI
        push    ESI
        mov     EDI, JumpTable
        mov     EAX, BufferLen
        mov     ECX, $100
        REPNE   STOSD
        mov     EDX, GUpcaseLUT
        mov     ECX, BufferLen
        mov     EDI, JumpTable
        mov     ESI, Buffer
        dec     ECX
        XOR     EAX, EAX

@@loop:
        mov     AL, [ESI]
        lea     ESI, ESI + 1
        mov     AL, [EDX + EAX]
        mov     [EDI + EAX * 4], ECX
        dec     ECX
        jg      @@loop
        pop     ESI
        pop     EDI
    end;
end;

function BMPos(const aSource, aFind: Pointer; const aSourceLen, aFindLen: Integer; var JumpTable: TBMJumpTable): Pointer;
var
    LastPos: Pointer;
begin
    LastPos := Pointer(Integer(aSource) + aSourceLen - 1);
    asm
        push    ESI
        push    EDI
        push    EBX
        mov     EAX, aFindLen
        mov     ESI, aSource
        lea     ESI, ESI + EAX - 1
        std
        mov     EBX, JumpTable

@@comparetext:
        cmp     ESI, LastPos
        jg      @@NotFound
        mov     EAX, aFindLen
        mov     EDI, aFind
        mov     ECX, EAX
        push    ESI //Remember where we are
        lea     EDI, EDI + EAX - 1
        XOR     EAX, EAX

@@CompareNext:
        mov     al, [ESI]
        cmp     al, [EDI]
        jne     @@LookAhead
        lea     ESI, ESI - 1
        lea     EDI, EDI - 1
        dec     ECX
        jz      @@Found
        jmp     @@CompareNext

@@LookAhead:
    //Look up the char in our Jump Table
        pop     ESI
        mov     al, [ESI]
        mov     EAX, [EBX + EAX * 4]
        lea     ESI, ESI + EAX
        jmp     @@CompareText

@@NotFound:
        mov     Result, 0
        jmp     @@TheEnd

@@Found:
        pop     EDI //We are just popping, we don't need the value
        inc     ESI
        mov     Result, ESI

@@TheEnd:
        cld
        pop     EBX
        pop     EDI
        pop     ESI
    end;
end;

function BMPosNoCase(const aSource, aFind: Pointer; const aSourceLen, aFindLen: Integer; var JumpTable: TBMJumpTable): Pointer;
var
    LastPos: Pointer;
begin
    LastPos := Pointer(Integer(aSource) + aSourceLen - 1);
    asm
        push    ESI
        push    EDI
        push    EBX
        mov     EAX, aFindLen
        mov     ESI, aSource
        lea     ESI, ESI + EAX - 1
        std
        mov     EDX, GUpcaseLUT

@@comparetext:
        cmp     ESI, LastPos
        jg      @@NotFound
        mov     EAX, aFindLen
        mov     EDI, aFind
        push    ESI //Remember where we are
        mov     ECX, EAX
        lea     EDI, EDI + EAX - 1
        XOR     EAX, EAX

@@CompareNext:
        mov     al, [ESI]
        mov     bl, [EDX + EAX]
        mov     al, [EDI]
        cmp     bl, [EDX + EAX]
        jne     @@LookAhead
        lea     ESI, ESI - 1
        lea     EDI, EDI - 1
        dec     ECX
        jz      @@Found
        jmp     @@CompareNext

@@LookAhead:
    //Look up the char in our Jump Table
        pop     ESI
        mov     EBX, JumpTable
        mov     al, [ESI]
        mov     al, [EDX + EAX]
        mov     EAX, [EBX + EAX * 4]
        lea     ESI, ESI + EAX
        jmp     @@CompareText

@@NotFound:
        mov     Result, 0
        jmp     @@TheEnd

@@Found:
        pop     EDI //We are just popping, we don't need the value
        inc     ESI
        mov     Result, ESI

@@TheEnd:
        cld
        pop     EBX
        pop     EDI
        pop     ESI
    end;
end;

//×Ö·û´®Í³¼Æ
function StrCount(Sub, S: string): Integer;
var
    ps, psub, tempps: PChar;
    step: Integer;
begin
    ps := PChar(S);
    psub := PChar(Sub);
    Result := 0;
    step := Length(Sub);
    while true do
    begin
        tempps := StrPos(ps, psub);
        if tempps = nil then
            Break
        else
        begin
            ps := tempps + step;
            Inc(Result);
        end;
    end;
end;

function FieldCount(const strRecord, strFs: string): integer;
begin
    result := StrCount(LowerCase(strFs), LowerCase(strRecord));
    if result < 1 then
        exit;
end;

//Í¨¹ý×Ö¶ÎÃû³Æ»ñÈ¡×Ö¶ÎÖµ
function GetFieldValueByName(RecordStr, FieldName: string; From: Integer = 1; Surround: string = '<>'): string;
var
    FieldValueStr, strFieldName: string;
    i, iNums: Integer;
    strFlag, ChLeft, ChRight: string;
    iBegin, iEnd: integer;
begin
    Result := '';
    FieldValueStr := RecordStr;
    iNums := FieldCount(FieldName, '.');
    for i := 0 to iNums do
    begin
        strFieldName := FieldValue('.', FieldName, i);
        if strFieldName = '' then
            continue;

        ChLeft := Surround[1];
        ChRight := Surround[2];

        strFlag := ChLeft + FieldName + ChRight;
        iBegin := FastPosNoCase(RecordStr, strFlag, Length(RecordStr), Length(strFlag), from);
        if (iBegin <= 0) then
            exit;
        iBegin := iBegin + Length(strFlag);

        strFlag := ChLeft + '/' + FieldName + ChRight;
        iEnd := FastPosNoCase(RecordStr, strFlag, Length(RecordStr), Length(strFlag), iBegin);
        if (iEnd <= 0) then
            exit;

        FieldValueStr := copy(RecordStr, iBegin, iEnd - iBegin);
    end;
    Result := FieldValueStr;
end;

function FieldValue(strSplit: string; str: string; iField: integer; cs: Boolean = False): string;
var
    i, ipos: integer;
    pString, pTmp: PChar;
    strFs, strRecord, strTmpRecord: string;
begin
    strFs := strSplit;
    strRecord := str;

    //ÓÅÏÈ´¦ÀíiField=FIDX_LAST(2147483647)
    //Ä¿Ç°´úÂëÐ§ÂÊ²»¸ß, ÈÕºóÓÅ»¯...
    if iField = FIDX_LAST then
    begin
        //
        ipos := SmartPos(strFs, strRecord, false, length(strRecord), false);
        result := copy(strRecord, 1, ipos);

        //ÊÇ·ñÇ°Ò»Ìõ
        ipos := SmartPos(strFs, result, false, length(result), false);
        if ipos > 0 then
            result := copy(result, ipos, length(result) - ipos);

        exit;
    end;

    try
        pString := @strRecord[1];
        for i := 0 to iField - 1 do
        begin
            if cs = False then
            begin
                ipos := NcPos(strFs, pString);
                if ipos > 0 then
                    pTmp := pchar(pString) + ipos - 1
                else
                    pTmp := nil;
            end
            else
            begin
                pTmp := AnsiStrPos(pchar(pString), pchar(strFs));
            end;

            if pTmp <> nil then
            begin
                pString := pTmp + length(strFs);
            end
            else
            begin
                pString := nil;
                break;
            end;
        end;

        strTmpRecord := string(pString);
        if cs = False then
            ipos := NcPos(strFs, strTmpRecord)
        else
            ipos := Pos(strFs, strTmpRecord);
        if ipos <> 0 then
            result := copy(strTmpRecord, 1, ipos - 1)
        else
            result := strTmpRecord;
    except
        result := '';
    end;
end;

//²»Çø·Ö´óÐ¡Ð´µÄpos
function NCPos(sub, source: string): integer;
begin
    Result := Pos(AnsiLowerCase(sub), AnsiLowerCase(source));
end;

function GetChineseWord(Text: string; len: Integer = 0): WideString;
var
    i, cnt: Integer;
    s: WideString;
begin
    Result := '';
    s := WideString(text);
    cnt := 0;
    if len = 0 then
        len := 999999999;
    for i := 1 to Length(s) do
    begin   //ºº×ÖµÄ·¶Î§
        if ((s[i] >= #$4E00) and (s[i] <= #$9FA5)) or ((s[i] >= #$F900) and (s[i] <= #$FA2D)) then
        begin
            Result := Result + s[i];
            inc(cnt);
            if cnt >= len then
                Break;
        end;
    end;
end;

//ÅÐ¶ÏÊÇ·ñÊÇGBK 2500¸ö³£ÓÃ×Ö
function IsGBK(Text: string; DoNotJudgeLength: Boolean = False): Boolean;
const
    sWord = ',Ò»,ÒÒ,¶þ,Ê®,¶¡,³§,Æß,²·,ÈË,Èë,°Ë,¾Å,¼¸,¶ù,ÁË,Á¦,ÄË,µ¶,ÓÖ,Èý,ÓÚ,¸É,¿÷,Ê¿,¹¤,ÍÁ,²Å,´ç,ÏÂ,´ó,ÕÉ,Óë,Íò,ÉÏ,Ð¡,' + '¿Ú,½í,É½,Ç§,Æò,´¨,ÒÚ,¸ö,É×,¾Ã,·²,¼°,Ï¦,Íè,Òå,Ö®,Ê¬,¹­,¼º,ÒÑ,×Ó,ÎÀ,Ò²,Å®,·É,ÈÐ,Ï°,²æ,Âí,Ïç,·á,Íõ,¾®,¿ª,·ò,' + 'Ìì,ÎÞ,ÔÆ,Ôú,ÒÕ,Ä¾,Îå,Ö§,Ìü,²»,Ì«,È®,Çø,Àú,ÓÈ,ÓÑ,Æ¥,³µ,¾Þ,ÑÀ,ÍÍ,±È,»¥,ÇÐ,ÈÕ,ÖÐ,¸Ô,±´,ÄÚ,Ë®,¼û,Îç,Å£,ÊÖ,Ã«,' + 'Æø,Éý,Ê²,Æ¬,ÆÍ,»¯,³ð,±Ò,ÈÔ,½ö,½ï,×¦,·´,½é,¸¸,´Ó,½ñ,Ð×,²Ö,ÔÂ,ÊÏ,Îð,Ç·,·ç,µ¤,ÔÈ,ÎÚ,·ï,¹´,ÎÄ,Áù,·½,»ð,Îª,¶·,' +
        'Òä,¶©,ÈÏ,ÐÄ,³ß,Òý,³ó,°Í,¿×,¶Ó,°ì,ÒÔ,Ë«,Êé,»Ã,Óñ,¿¯,Ê¾,Ä©,Î´,»÷,´ò,ÆË,°Ç,¹¦,ÈÓ,È¥,¸Ê,ÊÀ,¹Å,½Ú,±¾,Êõ,¿É,±û,' + '×ó,À÷,ÓÒ,Ê¯,²¼,Áú,Æ½,Ãð,Ôþ,Õ¼,Òµ,¾É,Ë§,¹é,ÇÒ,µ©,Ä¿,Ò¶,¼×,Éê,¶£,µç,ÓÉ,Ê·,Ö»,Ñë,ÐÖ,µð,½Ð,Áí,ß¶,Ì¾,ËÄ,Éú,Ê§,' + 'ºÌ,Çð,¸¶,ÃÇ,ÒÇ,°×,×Ð,Ëû,³â,¹Ï,ºõ,´Ô,Áî,ÓÃ,Ë¦,Ó¡,ÀÖ,¾ä,´Ò,²á,·¸,Íâ,Äñ,Îñ,°ü,¼¢,Ö÷,ÊÐ,Á¢,ÉÁ,À¼,°ë,ºº,Äþ,Ñ¨,' + 'Ëü,ÌÖ,Ð´,ÈÃ,Àñ,Ñµ,±Ø,Òé,Ñ¶,¼Ç,ÓÀ,Ë¾,Äá,Ãñ,³ö,ÁÉ,ÄÌ,Å«,¼Ó,ÕÙ,Æ¤,±ß,Ê¥,¶Ô,Ì¨,Ã¬,Ë¿,Ê½,ÐÌ,¶¯,¿¸,ËÂ,¼ª,¿Û,ÀÏ,' +
        'Ö´,¹®,»ø,À©,É¨,µØ,Ñï,³¡,¶ú,¹²,Ã¢,ÑÇ,Ö¥,Ðà,ÆÓ,»ú,È¨,¹ý,³¼,ÔÙ,Ð­,ÔÚ,ÓÐ,°Ù,´æ,¶ø,Ò³,½³,¿ä,¶á,»Ò,´ï,ÁÐ,ËÀ,¹ì,' + 'Ð°,»®,Âõ,±Ï,ÖÁ,´Ë,Õê,Ê¦,³¾,¼â,ÁÓ,¹â,µ±,Ôç,ÍÂ,ÍÅ,Í¬,µõ,³Ô,Òò,Îü,Âð,Óì,·«,Ëê,»Ø,Æñ,¸Õ,Ôò,Èâ,Íø,Äê,Öì,ÏÈ,Öñ,' + 'Ç¨,ÇÇ,Î°,´«,Æ¹,ÅÒ,ÐÝ,Îé,·ü,¼þ,ÈÎ,ÉË,¼Û,·Ý,»ª,Ñö,·Â,»ï,Î±,×Ô,Ñª,Ïò,ËÆ,ºó,ÐÐ,ÖÛ,È«,»á,É±,ºÏ,Õ×,Æó,ÖÚ,Ò¯,¼¡,' + '¶ä,ÔÓ,Î£,¸÷,Ãû,¶à,Õù,É«,×³,³å,±ù,×¯,Çì,Òà,Áõ,Æë,½»,´Î,ÒÂ,²ú,¾ö,³ä,Íý,±Õ,ÎÊ,´³,Ñò,²¢,¹Ø,Ã×,µÆ,ÖÝ,º¹,Ã¦,ÐË,' +
        'Óî,ÊØ,Õ¬,×Ö,°²,½²,¾ü,Ðí,ÂÛ,Å©,·í,Éè,·Ã,Ñ°,ÄÇ,Ñ¸,¾¡,µ¼,Òì,Ëï,Õó,Ñô,ÊÕ,½×,Òõ,·À,¼é,Èç,¸¾,Ï·,Óð,¹Û,ºì,ÏË,¼¶,' + 'Ô¼,¼Í,³Û,Ñ²,ÊÙ,Åª,Âó,ÐÎ,½ø,½ä,ÍÌ,ÔË,·ö,¸§,Ì³,¼¼,»µ,ÈÅ,¾Ü,ÕÒ,Åú,³¶,Ö·,×ß,³­,°Ó,¹±,¹¥,³à,ÕÛ,×¥,°ç,ÇÀ,Í¶,·Ø,' + '¿¹,¿Ó,·»,¶¶,»¤,¿Ç,Ö¾,Å¤,¿é,Éù,°Ñ,½Ù,Ñ¿,»¨,ÇÛ,·Ò,²Ô,·¼,ÑÏ,Â«,ÀÍ,¿Ë,ËÕ,¸Ë,¸Ü,¶Å,²Ä,Àî,Ñî,Çó,¸ü,Êø,¶¹,Á½,Àö,' + 'Ò½,³½,Àø,·ñ,»¹,¼ß,À´,Á¬,²½,¼á,ºµ,Ê±,Îâ,Öú,ÏØ,Àï,´ô,Ô°,¿õ,Î§,Ñ½,ÄÐ,À§,³³,´®,Ô±,Ìý,·Ô,´µ,ÎØ,°É,ºð,±ð,¸Ú,ÕÊ,' +
        '²Æ,Õë,¶¤,¸æ,ÎÒ,ÂÒ,Àû,Íº,Ðã,Ë½,Ã¿,Ìå,ºÎ,µ«,Éì,Ó¶,µÍ,Äã,×¡,Î»,°é,Éí,Ôí,·ð,½ü,³¹,ÒÛ,·µ,Óà,Ï£,×ø,¹È,Í×,º¬,ÁÚ,' + '²í,¸Î,¶Ç,³¦,¹ê,Ãâ,¿ñ,ÓÌ,½Ç,É¾,·¹,Òû,Ïµ,ÑÔ,¶³,×´,Ä¶,¿ö,´²,¿â,ÁÆ,Ó¦,Àä,Õâ,Ðò,ÐÁ,Æú,Ò±,Íü,ÏÐ,¼ä,ÃÆ,ÅÐ,Ôî,²Ó,' + 'µÜ,Íô,É³,Æû,ÎÖ,·º,³Á,»³,ÓÇ,ËÎ,ºê,ÀÎ,¾¿,Çî,ÔÖ,Á¼,Ö¤,Æô,ÆÀ,²¹,³õ,Éç,Ê¶,Ëß,Õï,´Ê,Òë,¾ý,Áé,¼´,²ã,Äò,Î²,³Ù,¾Ö,' + '¼Ê,Â½,°¢,³Â,×è,¸½,Ãî,Ñý,·Á,¾¢,¼¦,Çý,´¿,É´,ÄÉ,¸Ù,²µ,×Ý,·×,Ö½,ÎÆ,·Ä,Â¿,Å¦,·î,Íæ,»·,Îä,Çà,Ôð,ÏÖ,Ä¨,Â£,°Î,¼ð,' +
        'µ£,Ì¹,Ñº,³é,¹Õ,ÍÏ,ÅÄ,Õß,¶¥,²ð,Óµ,µÖ,¾Ð,ÊÆ,±§,À¬,À­,À¹,ÆÂ,Åû,²¦,Ôñ,Ì§,Æä,È¡,¿à,Èô,Ã¯,Æ»,Ãç,Ó¢,ÇÑ,¾¥,Ã©,ÁÖ,' + 'Ö¦,±­,¹ñ,Îö,°å,ËÉ,Ç¹,¹¹,½Ü,Êö,Õí,É¥,ÊÂ,´Ì,Ôæ,Óê,Âô,¿ó,Âë,²Þ,±¼,Ææ,·Ü,Ì¬,Å·,Â¢,ÆÞ,ºä,Çê,×ª,Õ¶,µ½,·Ç,Êå,¿Ï,' + '³Ý,Ð©,»¢,Â²,Éö,ÏÍ,¹û,Î¶,À¥,¹ú,²ý,³©,Ã÷,Ò×,°º,µä,¹Ì,ÖÒ,¸À,ºô,Ãù,Ó½,ÄØ,°¶,ÑÒ,Ìû,ÂÞ,ÖÄ,Áë,¿­,°Ü,Í¼,µö,ÖÆ,Öª,' + '¹Ô,¹Î,¸Ñ,ºÍ,¼¾,Î¯,¼Ñ,ÊÌ,¹©,Ê¹,Àý,°æ,Ö¶,Õì,²à,Æ¾,ÇÈ,Åå,»õ,ÒÀ,µÄ,ÆÈ,ÖÊ,ÐÀ,Õ÷,Íù,ÅÀ,±Ë,¾¶,Ëù,°Ö,²É,ÊÜ,Èé,Ì°,' +
        'Äî,Æ¶,·ô,·Î,Ö«,Ö×,ÕÍ,Åó,¹É,·Ê,·þ,Ð²,ÖÜ,»è,Óã,ÍÃ,ºü,ºö,¹·,±¸,ÊÎ,±¥,ËÇ,±ä,¾©,Ïí,¸®,µ×,¼Á,¾»,Ã¤,·Å,¿Ì,Óý,Õ¢,' + 'ÄÖ,Ö£,È¯,¾í,µ¥,³´,´¶,¿»,Ñ×,Â¯,Ä­,Ç³,·¨,Ð¹,ºÓ,Õ´,Àá,ÓÍ,²´,ÑØ,Ó¾,Äà,·Ð,²¨,ÆÃ,Ôó,ÖÎ,²À,ÐÔ,¹Ö,Ñ§,±¦,×Ú,¶¨,ÒË,' + 'Éó,Öæ,¹Ù,¿Õ,Á±,Êµ,ÊÔ,ÀÉ,Ê«,¼ç,·¿,³Ï,³Ä,ÉÀ,Ñ¯,¸Ã,Ïê,½¨,Ëà,Â¼,Á¥,¾Ó,½ì,Ë¢,Çü,ÏÒ,³Ð,ÃÏ,¹Â,ÏÞ,ÃÃ,¹Ã,½ã,ÐÕ,Ê¼,' + '¼Ý,²Î,¼è,Ïß,Á·,×é,Ï¸,Ê»,ÍÕ,ÉÜ,¾­,¹á,×à,´º,°ï,Õä,²£,¶¾,ÐÍ,³Ö,Ïî,¿å,¿æ,³Ç,ÄÓ,Õþ,¸°,ÕÔ,µ²,Í¦,À¨,Ë©,Ê°,Ìô,Ö¸,' +
        'µæ,Õõ,¼·,Æ´,ÍÚ,°´,Éõ,¸ï,¼ö,Ïï,´ø,²Ý,¼ë,²è,»Ä,Ã£,µ´,ÈÙ,¹Ê,Ò©,±ê,¿Ý,±ú,¶°,Ïà,²é,°Ø,Áø,Öù,ÊÁ,À¸,Ê÷,Òª,ÏÌ,Íþ,' + 'Àå,ºñ,Æö,¿³,Ãæ,ÄÍ,Ë£,Ç£,²Ð,Ñê,Çá,Ñ»,½Ô,±³,Õ½,µã,ÁÙ,ÀÀ,Êú,³¢,ÊÇ,ÅÎ,Õ£,ºå,ÏÔ,ÑÆ,Ã°,Ó³,ÐÇ,Î¸,¹ó,½ç,ºç,Ïº,ÒÏ,' + 'Ë¼,Âì,Ëä,Æ·,ÑÊ,Âî,»©,ÔÛ,Ïì,¹þ,Ò§,¿È,ÄÄ,Ì¿,Ï¿,·£,¼ú,Ìù,¹Ç,¸Ö,Ô¿,¹³,Ð¶,¾Ø,Ôõ,Éü,Ñ¡,ÊÊ,Ãë,Ïã,ÖÖ,Çï,¿Æ,ÖØ,¸´,' + '¸Í,¶Î,±ã,Á©,´û,Ë³,ÐÞ,±£,´Ù,Îê,¼ó,Ë×,·ý,ÐÅ,»Ê,Èª,¹í,ÇÖ,ÂÉ,ºÜ,Ðë,Ðð,½£,ÌÓ,Ê³,Åè,µ¨,Ê¤,°û,ÅÖ,Âö,Ãã,ÏÁ,Ê¨,¶À,' +
        '½Æ,Óü,ºÝ,Ã³,Ô¹,¼±,ÈÄ,Ê´,½È,±ý,Íä,½«,½±,°§,¼£,Í¥,´¯,°Ì,×Ë,Ç×,Òô,µÛ,Ê©,ÎÅ,·§,¸ó,²î,Ñø,ÃÀ,½ª,ÅÑ,ËÍ,Àà,ÃÔ,Ç°,' + 'Ê×,Äæ,×Ü,Á¶,Õ¨,ÅÚ,ÀÃ,Ìê,½½,×Ç,¶´,²â,Ï´,»î,ÅÉ,Ç¢,È¾,ÖÞ,»ë,Å¨,½ò,ºã,»Ö,Ç¡,ÄÕ,ºÞ,¾Ù,¾õ,Ðû,ÊÒ,¹¬,ÏÜ,Í»,´©,ÇÔ,' + '¿Í,¹Ú,×æ,Éñ,×£,Îó,ÓÕ,Ëµ,ËÐ,¿Ñ,ÍË,¼È,ÎÝ,Öç,·Ñ,¶¸,Ã¼,ÏÕ,Ôº,ÍÞ,ÀÑ,ÒÌ,Òö,½¿,Å­,¼Ü,ºØ,Ó¯,ÓÂ,µ¡,Èá,½á,ÈÆ,½¾,»æ,' + '¸ø,Âç,Âæ,¾ø,½Ê,Í³,¸û,ºÄ,ÑÞ,Ì©,Öé,°à,ËØ,Õµ,·Ë,ÀÌ,ÔÔ,²¶,Õñ,ÔØ,¸Ï,Æð,ÑÎ,ÉÓ,Äó,Âñ,×½,À¦,¾è,Ëð,¶¼,ÕÜ,ÊÅ,¼ñ,»»,' +
        'ºø,°¤,³Ü,µ¢,¹§,Á«,Äª,ºÉ,»ñ,½ú,¶ñ,Õæ,¿ò,Í©,Öê,ÇÅ,ÌÒ,¸ñ,Ð£,ºË,Ñù,¸ù,Ë÷,¸ç,ËÙ,¶º,Àõ,Åä,³á,´¡,ÆÆ,Ô­,Ì×,Öð,ÁÒ,' + 'Êâ,¹Ë,½Î,½Ï,¶Ù,±Ð,ÖÂ,²ñ,×À,ÂÇ,¼à,½ô,µ³,Ïþ,Ñ¼,»Î,ÉÎ,ÔÎ,ÎÃ,ÉÚ,¿Þ,¶÷,»½,·å,Ô²,Ôô,»ß,Ç®,Ç¯,×ê,Ìú,Áå,Ç¦,È±,Ñõ,' + 'ÌØ,Îþ,Ôì,³Ë,µÐ,³Ó,×â,»ý,Ñí,ÖÈ,³Æ,ÃØ,Í¸,Ëñ,Õ®,½è,Öµ,ÌÈ,¾ã,³«,ºò,¸©,±¶,¾ë,½¡,³ô,Éä,¹ª,Ï¢,Í½,Ðì,½¢,²Õ,°ã,º½,' + 'Í¾,ÄÃ,µù,°®,ËÌ,ÎÌ,´à,Ö¬,ÐØ,¸ì,Ôà,½º,Áô,Öå,¶ö,Áµ,½°,½¬,Ë¥,¸ß,Ï¯,×¼,×ù,¼¹,Ö¢,²¡,¼²,ÌÛ,Æ£,Ð§,Àë,ÌÆ,×Ê,Á¹,Õ¾,' +
        'ÆÊ,¾º,²¿,ÅÔ,ÂÃ,Ðó,ÔÄ,Ðß,ÁÏ,Òæ,¼æ,·³,ÉÕ,Öò,ÑÌ,µÝ,ÌÎ,Õã,ÀÔ,¾Æ,Éæ,Ïû,ºÆ,º£,Í¿,Ô¡,¸¡,Á÷,Èó,ÀË,½þ,ÕÇ,ÌÌ,Ó¿,Îò,' + 'ÇÄ,»Ú,¼Ò,Ïü,Ñç,±ö,Õ­,ÈÝ,Ô×,°¸,Çë,¶Á,ÉÈ,Íà,Ðä,ÅÛ,±»,Ïé,¿Î,Ë­,µ÷,Ô©,ÁÂ,Ì¸,Òê,°þ,¿Ò,Õ¹,¾ç,Ð¼,Èõ,Åã,Óé,Äï,Í¨,' + 'ÄÜ,ÄÑ,Ô¤,É£,¾î,Ðå,Ñé,¼Ì,Çò,Àí,Åõ,¶Â,Ãè,Óò,ÑÚ,µô,¶Ñ,ÍÆ,ÏÆ,ÊÚ,½Ì,ÌÍ,ÂÓ,Åà,½Ó,¿Ø,Ì½,¾Ý,¾ò,Ö°,»ù,Öø,ÀÕ,»Æ,ÃÈ,' + 'ÂÜ,¾ú,Æ¼,²¤,Óª,Ðµ,ÃÎ,ÉÒ,Ã·,¼ì,Êá,ÌÝ,Í°,¾È,¸±,Ë¬,Áû,Ï®,Ê¢,Ñ©,¸¨,Á¾,Ðé,È¸,ÌÃ,³£,³×,³¿,Õö,ÃÐ,ÑÛ,Íí,×Ä,¾à,Ô¾,' +
        'ÂÔ,Éß,ÀÛ,³ª,»¼,Î¨,ÑÂ,Õ¸,³ç,È¦,Í­,²ù,Òø,Ìð,Àæ,±¿,Áý,µÑ,·û,µÚ,Ãô,×ö,´ü,ÓÆ,³¥,ÊÛ,Í£,Æ«,¼Ù,µÃ,ÏÎ,ÅÌ,´¬,Ð±,ºÐ,' + '¸ë,Ï¤,Óû,²Ê,Áì,½Å,²±,Á³,ÍÑ,Ïó,¹»,²Â,Öí,ÁÔ,Ã¨,¹Ý,´Õ,¼õ,ºÁ,ÀÈ,¿µ,Ó¹,Â¹,µÁ,ÕÂ,¾¹,ÉÌ,×å,Ðý,Íû,ÂÊ,×Å,¸Ç,Õ³,´Ö,' + 'Á£,¶Ï,¼ô,ÊÞ,Çå,Ìí,ÁÜ,ÑÍ,Çþ,½¥,»ì,Óæ,ÌÔ,Òº,Éø,Çé,Ï§,²Ñ,µ¿,¾å,Ìè,¾ª,²Ò,¹ß,¿Ü,¼Ä,ËÞ,Ò¤,ÃÜ,Ä±,»Ñ,»ö,ÃÕ,´þ,¸Ò,' + 'ÍÀ,µ¯,Ëæ,µ°,Â¡,Òþ,»é,Éô,¾±,¼¨,Éþ,Î¬,Ãà,ÇÙ,°ß,Ìæ,¿î,¿°,´î,Ëþ,Ç÷,³¬,Ìá,µÌ,²©,½Ò,Ï²,²å,¾¾,ËÑ,Öó,Ô®,²Ã,¸é,Â§,' +
        '½Á,ÎÕ,Èà,Ë¹,ÆÚ,ÆÛ,Áª,¸ð,¶­,ÆÏ,¾´,´Ð,Âä,³¯,¹¼,¿û,°ô,Æå,Ö²,É­,¿Ã,¹÷,ÃÞ,Åï,×Ø,»Ý,»ó,±Æ,³ø,ÏÃ,Ó²,È·,Ñã,Ö³,ÁÑ,' + 'ÐÛ,±¯,×Ï,»Ô,³¨,ÉÍ,ÕÆ,Çç,Êî,×î,Á¿,Åç,¾§,À®,Óö,º°,¾°,¼ù,µø,ÅÜ,Öë,òÑ,ºÈ,Î¹,´­,ºí,·ù,Ã±,¶Ä,Åâ,Á´,Ïú,Ëø,³ú,¹ø,' + 'Ðâ,·æ,Èñ,¶Ì,ÖÇ,Ìº,¶ì,Ê£,ÉÔ,³Ì,Ï¡,Ë°,¿ð,µÈ,Öþ,²ß,É¸,Í²,´ð,½î,¸µ,ÅÆ,±¤,¼¯,°Â,½Ö,³Í,Óù,Ñ­,Í§,Êæ,·¬,ÊÍ,ÇÝ,À°,' + 'Æ¢,Ç»,Â³,»«,ºï,È»,²ö,×°,Âù,¾Í,Í´,Í¯,À«,ÉÆ,ÏÛ,ÆÕ,·à,×ð,µÀ,Ôü,Êª,ÎÂ,¿Ê,»¬,Íå,¶É,ÓÎ,×Ì,¸È,·ß,»Å,¶è,À¢,Óä,¿®,' +
        '¸î,º®,¸»,´Ü,ÎÑ,´°,±é,Ô£,¿ã,È¹,Ð»,Ò¥,Ç«,Êô,ÂÅ,¸ô,Ï¶,Ðõ,¶Ð,»º,±à,Æ­,Ôµ,Èð,»ê,ËÁ,Éã,Ãþ,Ìî,²«,°Ú,Ð¯,°á,Ò¡,¸ã,' + 'ÌÁ,Ì¯,Ëâ,ÇÚ,Èµ,À¶,Ä¹,Ä»,Åî,Ðî,ÃÉ,Õô,Ï×,½û,³þ,Ïë,»±,Àµ,³ê,¸Ð,°­,±®,Ëé,Åö,Íë,Âµ,À×,Áã,Îí,±¢,Áä,¼ø,¾¦,Ë¯,²Ç,' + '±É,ÓÞ,Å¯,ÃË,Ðª,°µ,ÕÕ,¿ç,Ìø,¹ò,Â·,·ä,É¤,ÖÃ,×ï,ÕÖ,´í,Îý,Âà,´¸,½õ,¼ü,¾â,°«,´Ç,³í,³î,³ï,Ç©,¼ò,Êó,´ß,Éµ,Ïñ,¶ã,' + 'Î¢,Óú,Ò£,Ñü,ÐÈ,´¥,½â,½´,Ìµ,Á®,ÐÂ,ÔÏ,Òâ,Á¸,Êý,¼å,ËÜ,´È,Ãº,»Í,Âú,Ä®,Ô´,ÂË,ÀÄ,ÌÏ,Ïª,Áï,¹ö,±õ,É÷,Óþ,Èû,½÷,±Ù,' +
        'ÕÏ,ÏÓ,¼Þ,µþ,·ì,²ø,¾²,±Ì,Á§,Ç½,Æ²,¼Î,´Ý,¾³,Õª,Ë¤,¾Û,±Î,Ä½,Äº,Ãï,Ä£,Áñ,°ñ,Õ¥,¸è,Ôâ,¿á,Äð,Ëá,´Å,Ô¸,Ðè,±×,ÉÑ,' + 'À¯,Ó¬,Ö©,×¬,ÇÂ,¶Í,Îè,ÎÈ,Ëã,Âá,¹Ü,ÁÅ,±Ç,Ä¤,²²,°ò,ÏÊ,ÒÉ,Âø,¹ü,ÇÃ,ºÀ,¸à,ÕÚ,¸¯,ÊÝ,À±,½ß,¶Ë,Ï¨,ÈÛ,Æá,Æ¯,Âþ,µÎ,' + 'ÑÝ,Â©,Âý,Õ¯,Èü,²ì,ÃÛ,Æ×,ÄÛ,´ä,ÐÜ,µÊ,Ââ,Ëõ,»Û,Ëº,Èö,È¤,ÌË,³Å,²¥,Ôö,´Ï,Ð¬,½¶,Êß,ºá,²Û,Ó£,Ïð,Æ®,´×,×í,Õð,Ã¹,' + 'Â÷,Ìâ,±©,Ï¹,Ó°,Ìß,Ì¤,²È,Öö,Ä«,Õò,¿¿,µ¾,Àè,¸å,¼Ú,Ïä,¼ý,Æª,½©,ÌÉ,ËÒ,Ï¥,ÌÅ,Êì,Ä¦,ÑÕ,Òã,ºý,×ñ,Ç±,³±,¶®,¶î,Î¿,' +
        'Åü,²Ù,Ñà,Êí,Ð½,±¡,µß,éÙ,ÐÑ,²Í,×ì,Ìã,Æ÷,Ôù,Ä¬,¾µ,ÔÞ,Àº,Ñû,ºâ,Åò,µñ,Ä¥,Äý,±æ,±ç,ÌÇ,¸â,È¼,Ôè,±Ü,½É,´÷,²Á,¾Ï,' + '²Ø,Ëª,Ï¼,ÇÆ,Ëë,·±,±è,Ó®,Ôã,¿·,Ôï,±Û,Òí,Öè,±Þ,¸²,±Ä,Á­,·­,Ó¥,¾¯,ÅÊ,¶×,²ü,°ê,±¬,½®,ÈÀ,Ò«,Ôê,½À,ÈÂ,¼®,Ä§,¹à,' + '´À,°Ô,Â¶,ÄÒ,¹Þ,×¨,Ôª,ÈÊ,³¤,»§,¼Æ,Õý,ÇÉ,Ìï,ºÅ,¶¬,´¦,ÔÐ,·¢,ÍÐ,¿¼,¼Ð,³É,Éà,¶ª,´´,É¡,Âò,»¶,Î¥,Ô¶,È´,±¨,³Ê,¶¢,' + '¹À,±ø,Íê,¿ì,ÈÌ,Å¬,¹æ,±í,Ö±,·¶,Èí,ÂÖ,¹º,··,·Ï,½¼,Á¯,ÅÂ,½µ,ÉÂ,·â,¹Ò,ÄÏ,ºú,Ï÷,Ê¡,ÖÓ,³®,Òß,·è,Ñó,¼Ã,³ý,º¢,Íç,' +
        '²Ï,µµ,¹ð,Ãß,É¹,Ð¦,±Ê,ºæ,¿¾,Öî,ÀÊ,ÅÅ,½Ý,ÆÝ,Æ±,ÒÆ,Àç,ÏÚ,ÃÍ,ÂÌ,³ñ,³Ã,Ô½,½·,ÒÎ,ÍÜ,ÒÅ,°Á,óÝ,µÇ,É©,¹Ä,Ëú,¶½,Êä,' + '¾Ë,»Ù,Ì²,Á»,ÊÄ,½Ø,Ã²,ÆÇ,³·,×²,µÂ,Æ§,ÈÚ,Õû,ÂÝ,µ¸,ÉÙ,Ö¹,Íß,¹«,·¦,·Ö,È°,Óè,ÔÊ,±±,¿¨,¶«,ÏÉ,´ú,ÕÌ,Í·,»ã,Ö­,Ó×,' + 'Ä¸,¾À,Ñá,Ñ¹,Î÷,Çú,³æ,ÏÅ,ÑÓ,·¥,ÓÅ,¸º,Ö¼,Ñ®,Âè,Ëý,ºÃ,Å×,¾ù,Ð¢,¼«,ÐÓ,´å,ÓÊ,×ã,¶Ö,Áæ,²®,×÷,Éò,Ã»,¹µ,¼É,ÕÅ,¸Ä,' + 'ÕÐ,ÐÒ,°è,ÎÔ,»­,»ò,¾ß,Íú,ÉÐ,Îï,ÄÁ,´¹,Ãí,Ò¹,µê,Ðº,×¢,ÅÝ,µ®,»°,ÊÓ,×¤,ÖÕ,Ö¯,Ä³,Å²,»Ó,×©,ÑÐ,Íá,Å¿,Î·,×ò,¿´,°Ý,' +
        '¸×,¶È,ÁÁ,Í¤,È÷,ºé,½à,°À,±â,Óï,ÈÞ,°ó,ÀÝ,¿Ö,ÈÈ,Íì,ÏÄ,´½,Èè,°Õ,°¦,°¡,µ¹,Çã,ÒÐ,·Û,È­,Æ¿,¿í,º¦,ÔÃ,ÏÝ,ÌÕ,Áê,¾Õ,' + 'ÌÑ,²Ë,À²,Ò°,Ðü,Äú,Íµ,Å¼,ºÛ,Ñ÷,Âé,Æï,Ðø,Ð÷,Ôá,ÈÇ,É¢,±²,ÑÅ,ÔÝ,ÆÌ,Öý,ºÚ,´¢,°ø,½¹,Êè,Öà,Ç¿,¸Å,Â¥,ÓÜ,¶ê,Ç²,¸ú,' + 'ÍÈ,ÌÚ,¸¹,µî,Èº,¸£,òß,ËÔ,¿Å,Ç¸,¾«,Æì,ºû,µû,×Ù,±Ú,ÀÁ,¼¤,ÃÅ,Íö,¹ã,Ã´,ÌÀ,³Ø,½­,ÎÛ,Ó­,µº,ÂÑ,Ìõ,¸«,Ãü,½ð,Éá,´ý,' + '¶Ü,¿¡,×·,·ê,ÀÇ,Àê,ÄÔ,Áº,ÆÅ,Éî,µ­,ºþ,¸Û,Ñæ,Ôø,';
var
    i: Integer;
    cnt, maxcnt: Integer;
    s: WideString;
begin
    Result := True;
    s := GetChineseWord(Text, 50);
    if not DoNotJudgeLength then
    begin
        if Length(s) < 10 then
            Exit;
    end;

    cnt := 0;
    maxcnt := Length(s);
    for i := 1 to maxcnt do
    begin
        if Pos(s[i], sWord) > 0 then
        begin
            inc(cnt);
        end;
    end;

    if cnt / maxcnt < 0.6 then
        Result := False
    else
        Result := True;
end;

function Utf8ToGb2312(const unicodestr: string): string;
var
    SourceLength: Integer;
    DoneLength: Integer;
    AscNo: Integer;
    Byte1, Byte2, Byte3: Integer;
    GbStr: string;
begin
    GbStr := '';
    Byte1 := 0;
    Byte2 := 0;
    Byte3 := 0;

    if Trim(unicodestr) = '' then
        Exit;

    SourceLength := Length(UnicodeStr);
    DoneLength := 1;
    repeat
        AscNo := Ord(UnicodeStr[DoneLength]);
        case (AscNo and $E0) of
            $E0:
                begin
                    Byte1 := (AscNo and $0f) shl 12;
                    Inc(DoneLength);
                    if DoneLength > SourceLength then
                        Break;
                    AscNo := Ord(UnicodeStr[DoneLength]);
                    Byte2 := (AscNo and $3f) shl 6;
                    Inc(DoneLength);
                    if DoneLength > SourceLength then
                        Break;
                    AscNo := Ord(UnicodeStr[DoneLength]);
                    Byte3 := AscNo and $3f;
                end;
            $C0:
                begin
                    Byte1 := (AscNo and $1f) shl 6;
                    Inc(DoneLength);
                    if DoneLength > SourceLength then
                        Break;
                    AscNo := Ord(UnicodeStr[DoneLength]);
                    Byte2 := (AscNo and $3f);
                    Byte3 := 0;
                end;
            0..$bf:
                begin
                    Byte1 := AscNo;
                    Byte2 := 0;
                    Byte3 := 0;
                end;
        end; //case;
        GbStr := GBStr + Widechar(Byte1 + Byte2 + Byte3);
        Inc(DoneLength);
        if DoneLength > SourceLength then
            Break;
    until DoneLength >= SourceLength;

    Result := GbStr;
end;

function HtmlToGbk(html: string): string;
var
    i: Integer;
begin
    i := Pos('<!DOCTYPE html', html);
    if i > 0 then
        html := Copy(html, i, Length(html) + 100);

    if not IsGBK(html) then
    begin
        Result := Utf8ToAnsi(html);
        if Trim(Result) = '' then
            Result := Utf8ToGb2312(html);
        if Trim(Result) = '' then
            Result := html;
    end
    else
    begin
        Result := html;
    end;
end;

function SmartPos(const SearchStr, SourceStr: string; const CaseSensitive: Boolean = TRUE; const StartPos: Integer = 1; const ForwardSearch: Boolean = TRUE): Integer;
begin
  // NOTE:  When using StartPos, the returned value is absolute!
    if (CaseSensitive) then
        if (ForwardSearch) then
            Result := FastPos(SourceStr, SearchStr, Length(SourceStr), Length(SearchStr), StartPos)
        else
            Result := FastPosBack(SourceStr, SearchStr, Length(SourceStr), Length(SearchStr), StartPos)
    else if (ForwardSearch) then
        Result := FastPosNoCase(SourceStr, SearchStr, Length(SourceStr), Length(SearchStr), StartPos)
    else
        Result := FastPosBackNoCase(SourceStr, SearchStr, Length(SourceStr), Length(SearchStr), StartPos)
end;

function FastPos(const aSourceString, aFindString: string; const aSourceLen, aFindLen, StartPos: Integer): Integer;
var
    JumpTable: TBMJumpTable;
begin
  //If this assert failed, it is because you passed 0 for StartPos, lowest value is 1 !!
    Assert(StartPos > 0);
    if aFindLen < 1 then
    begin
        Result := 0;
        exit;
    end;
    if aFindLen > aSourceLen then
    begin
        Result := 0;
        exit;
    end;

    MakeBMTable(PChar(aFindString), aFindLen, JumpTable);
    Result := Integer(BMPos(PChar(aSourceString) + (StartPos - 1), PChar(aFindString), aSourceLen - (StartPos - 1), aFindLen, JumpTable));
    if Result > 0 then
        Result := Result - Integer(@aSourceString[1]) + 1;
end;

function FastPosBack(const aSourceString, aFindString: string; const aSourceLen, aFindLen, StartPos: Integer): Integer;
var
    SourceLen: Integer;
begin
    if aFindLen < 1 then
    begin
        Result := 0;
        exit;
    end;
    if aFindLen > aSourceLen then
    begin
        Result := 0;
        exit;
    end;

    if (StartPos = 0) or (StartPos + aFindLen > aSourceLen) then
        SourceLen := aSourceLen - (aFindLen - 1)
    else
        SourceLen := StartPos;

    asm
        push    ESI
        push    EDI
        push    EBX
        mov     EDI, aSourceString
        add     EDI, SourceLen
        Dec     EDI
        mov     ESI, aFindString
        mov     ECX, SourceLen
        Mov     Al, [ESI]

@ScaSB:
        cmp     Al, [EDI]
        jne     @NextChar

@CompareStrings:
        mov     EBX, aFindLen
        dec     EBX
        jz      @FullMatch

@CompareNext:
        mov     Ah, [ESI + EBX]
        cmp     Ah, [EDI + EBX]
        Jnz     @NextChar

@Matches:
        Dec     EBX
        Jnz     @CompareNext

@FullMatch:
        mov     EAX, EDI
        sub     EAX, aSourceString
        inc     EAX
        mov     Result, EAX
        jmp     @TheEnd

@NextChar:
        dec     EDI
        dec     ECX
        jnz     @ScaSB
        mov     Result, 0

@TheEnd:
        pop     EBX
        pop     EDI
        pop     ESI
    end;
end;

function FastPosBackNoCase(const aSourceString, aFindString: string; const aSourceLen, aFindLen, StartPos: Integer): Integer;
var
    SourceLen: Integer;
begin
    if aFindLen < 1 then
    begin
        Result := 0;
        exit;
    end;
    if aFindLen > aSourceLen then
    begin
        Result := 0;
        exit;
    end;

    if (StartPos = 0) or (StartPos + aFindLen > aSourceLen) then
        SourceLen := aSourceLen - (aFindLen - 1)
    else
        SourceLen := StartPos;

    asm
        push    ESI
        push    EDI
        push    EBX
        mov     EDI, aSourceString
        add     EDI, SourceLen
        Dec     EDI
        mov     ESI, aFindString
        mov     ECX, SourceLen
        mov     EDX, GUpcaseLUT
        XOR     EBX, EBX
        mov     Bl, [ESI]
        mov     Al, [EDX + EBX]

@ScaSB:
        mov     Bl, [EDI]
        cmp     Al, [EDX + EBX]
        jne     @NextChar

@CompareStrings:
        PUSH    ECX
        mov     ECX, aFindLen
        dec     ECX
        jz      @FullMatch

@CompareNext:
        mov     Bl, [ESI + ECX]
        mov     Ah, [EDX + EBX]
        mov     Bl, [EDI + ECX]
        cmp     Ah, [EDX + EBX]
        Jz      @Matches
//Go back to findind the first char
        POP     ECX
        Jmp     @NextChar

@Matches:
        Dec     ECX
        Jnz     @CompareNext

@FullMatch:
        POP     ECX
        mov     EAX, EDI
        sub     EAX, aSourceString
        inc     EAX
        mov     Result, EAX
        jmp     @TheEnd

@NextChar:
        dec     EDI
        dec     ECX
        jnz     @ScaSB
        mov     Result, 0

@TheEnd:
        pop     EBX
        pop     EDI
        pop     ESI
    end;
end;

procedure MakeBMTable(Buffer: PChar; BufferLen: Integer; var JumpTable: TBMJumpTable);
begin
    if BufferLen = 0 then
        raise Exception.Create('BufferLen is 0');
    asm
        push    EDI
        push    ESI
        mov     EDI, JumpTable
        mov     EAX, BufferLen
        mov     ECX, $100
        REPNE   STOSD
        mov     ECX, BufferLen
        mov     EDI, JumpTable
        mov     ESI, Buffer
        dec     ECX
        XOR     EAX, EAX

@@loop:
        mov     AL, [ESI]
        lea     ESI, ESI + 1
        mov     [EDI + EAX * 4], ECX
        dec     ECX
        jg      @@loop
        pop     ESI
        pop     EDI
    end;
end;

initialization
    //...
	{$IFNDEF LINUX}
    for I := 0 to 255 do
        GUpcaseTable[I] := Chr(I);
    CharUpperBuff(@GUpcaseTable[0], 256);
	{$ELSE}
    for I := 0 to 255 do
        GUpcaseTable[I] := UpCase(Chr(I));
	{$ENDIF}
    GUpcaseLUT := @GUpcaseTable[0];

finalization


end.


