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


//������ȡ����
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

function GetMatch(strText: string; strExp: string; idx: integer = 0;    //0��ʾ
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
    RegExpr.ModifierI := true; //�����ִ�Сд
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

    //2014-11-24 17:05 TIGER ���ʹ��widestring, ��Ӣ�ļ�������...��ʱ�޽�
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

        //2014-11-24 17:14 TIGER ���������
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
            ModifierI := true; //�����ִ�Сд
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



//���ݸ��Ե��������ʽ���в��Ҳ�������, ���Ʊ������
//Matchs����Ϊnil
//����ƥ�����
//2008-12-08 �������߸Ľ�һ������, Ϊ����ǰ�Ĵ��뱣�ּ���, ���Ӱ汾��
//2008-12-16 ����iContent����, ��ʾ���������
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
                //����������
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

//StartPos: ��1��ʼ
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

//�ַ���ͳ��
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

//ͨ���ֶ����ƻ�ȡ�ֶ�ֵ
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

    //���ȴ���iField=FIDX_LAST(2147483647)
    //Ŀǰ����Ч�ʲ���, �պ��Ż�...
    if iField = FIDX_LAST then
    begin
        //
        ipos := SmartPos(strFs, strRecord, false, length(strRecord), false);
        result := copy(strRecord, 1, ipos);

        //�Ƿ�ǰһ��
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

//�����ִ�Сд��pos
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
    begin   //���ֵķ�Χ
        if ((s[i] >= #$4E00) and (s[i] <= #$9FA5)) or ((s[i] >= #$F900) and (s[i] <= #$FA2D)) then
        begin
            Result := Result + s[i];
            inc(cnt);
            if cnt >= len then
                Break;
        end;
    end;
end;

//�ж��Ƿ���GBK 2500��������
function IsGBK(Text: string; DoNotJudgeLength: Boolean = False): Boolean;
const
    sWord = ',һ,��,��,ʮ,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,ʿ,��,��,��,��,��,��,��,��,��,��,С,' + '��,��,ɽ,ǧ,��,��,��,��,��,��,��,��,Ϧ,��,��,֮,ʬ,��,��,��,��,��,Ҳ,Ů,��,��,ϰ,��,��,��,��,��,��,��,��,' + '��,��,��,��,��,ľ,��,֧,��,��,̫,Ȯ,��,��,��,��,ƥ,��,��,��,��,��,��,��,��,��,��,��,��,ˮ,��,��,ţ,��,ë,' + '��,��,ʲ,Ƭ,��,��,��,��,��,��,��,צ,��,��,��,��,��,��,��,��,��,��,Ƿ,��,��,��,��,��,��,��,��,��,��,Ϊ,��,' +
        '��,��,��,��,��,��,��,��,��,��,��,��,˫,��,��,��,��,ʾ,ĩ,δ,��,��,��,��,��,��,ȥ,��,��,��,��,��,��,��,��,' + '��,��,��,ʯ,��,��,ƽ,��,��,ռ,ҵ,��,˧,��,��,��,Ŀ,Ҷ,��,��,��,��,��,ʷ,ֻ,��,��,��,��,��,߶,̾,��,��,ʧ,' + '��,��,��,��,��,��,��,��,��,��,��,��,��,��,˦,ӡ,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,Ѩ,' + '��,��,д,��,��,ѵ,��,��,Ѷ,��,��,˾,��,��,��,��,��,ū,��,��,Ƥ,��,ʥ,��,̨,ì,˿,ʽ,��,��,��,��,��,��,��,' +
        'ִ,��,��,��,ɨ,��,��,��,��,��,â,��,֥,��,��,��,Ȩ,��,��,��,Э,��,��,��,��,��,ҳ,��,��,��,��,��,��,��,��,' + 'а,��,��,��,��,��,��,ʦ,��,��,��,��,��,��,��,��,ͬ,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,' + 'Ǩ,��,ΰ,��,ƹ,��,��,��,��,��,��,��,��,��,��,��,��,��,α,��,Ѫ,��,��,��,��,��,ȫ,��,ɱ,��,��,��,��,ү,��,' + '��,��,Σ,��,��,��,��,ɫ,׳,��,��,ׯ,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,æ,��,' +
        '��,��,լ,��,��,��,��,��,��,ũ,��,��,��,Ѱ,��,Ѹ,��,��,��,��,��,��,��,��,��,��,��,��,��,Ϸ,��,��,��,��,��,' + 'Լ,��,��,Ѳ,��,Ū,��,��,��,��,��,��,��,��,̳,��,��,��,��,��,��,��,ַ,��,��,��,��,��,��,��,ץ,��,��,Ͷ,��,' + '��,��,��,��,��,��,־,Ť,��,��,��,��,ѿ,��,��,��,��,��,��,«,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,' + 'ҽ,��,��,��,��,��,��,��,��,��,��,ʱ,��,��,��,��,��,԰,��,Χ,ѽ,��,��,��,��,Ա,��,��,��,��,��,��,��,��,��,' +
        '��,��,��,��,��,��,��,ͺ,��,˽,ÿ,��,��,��,��,Ӷ,��,��,ס,λ,��,��,��,��,��,��,��,��,��,ϣ,��,��,��,��,��,' + '��,��,��,��,��,��,��,��,��,ɾ,��,��,ϵ,��,��,״,Ķ,��,��,��,��,Ӧ,��,��,��,��,��,ұ,��,��,��,��,��,��,��,' + '��,��,ɳ,��,��,��,��,��,��,��,��,��,��,��,��,��,֤,��,��,��,��,��,ʶ,��,��,��,��,��,��,��,��,��,β,��,��,' + '��,½,��,��,��,��,��,��,��,��,��,��,��,ɴ,��,��,��,��,��,ֽ,��,��,¿,Ŧ,��,��,��,��,��,��,��,Ĩ,£,��,��,' +
        '��,̹,Ѻ,��,��,��,��,��,��,��,ӵ,��,��,��,��,��,��,��,��,��,��,��,̧,��,ȡ,��,��,ï,ƻ,��,Ӣ,��,��,é,��,' + '֦,��,��,��,��,��,ǹ,��,��,��,��,ɥ,��,��,��,��,��,��,��,��,��,��,��,̬,ŷ,¢,��,��,��,ת,ն,��,��,��,��,' + '��,Щ,��,²,��,��,��,ζ,��,��,��,��,��,��,��,��,��,��,��,��,��,ӽ,��,��,��,��,��,��,��,��,��,ͼ,��,��,֪,' + '��,��,��,��,��,ί,��,��,��,ʹ,��,��,ֶ,��,��,ƾ,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,̰,' +
        '��,ƶ,��,��,֫,��,��,��,��,��,��,в,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,ä,��,��,��,բ,' + '��,֣,ȯ,��,��,��,��,��,��,¯,ĭ,ǳ,��,й,��,մ,��,��,��,��,Ӿ,��,��,��,��,��,��,��,��,��,ѧ,��,��,��,��,' + '��,��,��,��,��,ʵ,��,��,ʫ,��,��,��,��,��,ѯ,��,��,��,��,¼,��,��,��,ˢ,��,��,��,��,��,��,��,��,��,��,ʼ,' + '��,��,��,��,��,��,ϸ,ʻ,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,ͦ,��,˩,ʰ,��,ָ,' +
        '��,��,��,ƴ,��,��,��,��,��,��,��,��,��,��,��,ã,��,��,��,ҩ,��,��,��,��,��,��,��,��,��,��,��,��,Ҫ,��,��,' + '��,��,��,��,��,��,ˣ,ǣ,��,��,��,ѻ,��,��,ս,��,��,��,��,��,��,��,գ,��,��,��,ð,ӳ,��,θ,��,��,��,Ϻ,��,' + '˼,��,��,Ʒ,��,��,��,��,��,��,ҧ,��,��,̿,Ͽ,��,��,��,��,��,Կ,��,ж,��,��,��,ѡ,��,��,��,��,��,��,��,��,' + '��,��,��,��,��,˳,��,��,��,��,��,��,��,��,��,Ȫ,��,��,��,��,��,��,��,��,ʳ,��,��,ʤ,��,��,��,��,��,ʨ,��,' +
        '��,��,��,ó,Թ,��,��,ʴ,��,��,��,��,��,��,��,ͥ,��,��,��,��,��,��,ʩ,��,��,��,��,��,��,��,��,��,��,��,ǰ,' + '��,��,��,��,ը,��,��,��,��,��,��,��,ϴ,��,��,Ǣ,Ⱦ,��,��,Ũ,��,��,��,ǡ,��,��,��,��,��,��,��,��,ͻ,��,��,' + '��,��,��,��,ף,��,��,˵,��,��,��,��,��,��,��,��,ü,��,Ժ,��,��,��,��,��,ŭ,��,��,ӯ,��,��,��,��,��,��,��,' + '��,��,��,��,��,ͳ,��,��,��,̩,��,��,��,յ,��,��,��,��,��,��,��,��,��,��,��,��,׽,��,��,��,��,��,��,��,��,' +
        '��,��,��,��,��,��,Ī,��,��,��,��,��,��,ͩ,��,��,��,��,У,��,��,��,��,��,��,��,��,��,��,��,��,ԭ,��,��,��,' + '��,��,��,��,��,��,��,��,��,��,��,��,��,��,Ѽ,��,��,��,��,��,��,��,��,��,Բ,��,��,Ǯ,ǯ,��,��,��,Ǧ,ȱ,��,' + '��,��,��,��,��,��,��,��,��,��,��,��,͸,��,ծ,��,ֵ,��,��,��,��,��,��,��,��,��,��,��,Ϣ,ͽ,��,��,��,��,��,' + ';,��,��,��,��,��,��,֬,��,��,��,��,��,��,��,��,��,��,˥,��,ϯ,׼,��,��,֢,��,��,��,ƣ,Ч,��,��,��,��,վ,' +
        '��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,Ϳ,ԡ,��,��,��,��,��,��,��,ӿ,��,' + '��,��,��,��,��,��,խ,��,��,��,��,��,��,��,��,��,��,��,��,˭,��,ԩ,��,̸,��,��,��,չ,��,м,��,��,��,��,ͨ,' + '��,��,Ԥ,ɣ,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,̽,��,��,ְ,��,��,��,��,��,' + '��,��,Ƽ,��,Ӫ,е,��,��,÷,��,��,��,Ͱ,��,��,ˬ,��,Ϯ,ʢ,ѩ,��,��,��,ȸ,��,��,��,��,��,��,��,��,��,��,Ծ,' +
        '��,��,��,��,��,Ψ,��,ո,��,Ȧ,ͭ,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,ͣ,ƫ,��,��,��,��,��,б,��,' + '��,Ϥ,��,��,��,��,��,��,��,��,��,��,��,��,è,��,��,��,��,��,��,ӹ,¹,��,��,��,��,��,��,��,��,��,��,ճ,��,' + '��,��,��,��,��,��,��,��,��,��,��,��,��,Һ,��,��,ϧ,��,��,��,��,��,��,��,��,��,��,Ҥ,��,ı,��,��,��,��,��,' + '��,��,��,��,¡,��,��,��,��,��,��,ά,��,��,��,��,��,��,��,��,��,��,��,��,��,��,ϲ,��,��,��,��,Ԯ,��,��,§,' +
        '��,��,��,˹,��,��,��,��,��,��,��,��,��,��,��,��,��,��,ֲ,ɭ,��,��,��,��,��,��,��,��,��,��,Ӳ,ȷ,��,ֳ,��,' + '��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,ι,��,��,��,ñ,��,��,��,��,��,��,��,' + '��,��,��,��,��,̺,��,ʣ,��,��,ϡ,˰,��,��,��,��,ɸ,Ͳ,��,��,��,��,��,��,��,��,��,��,ѭ,ͧ,��,��,��,��,��,' + 'Ƣ,ǻ,³,��,��,Ȼ,��,װ,��,��,ʹ,ͯ,��,��,��,��,��,��,��,��,ʪ,��,��,��,��,��,��,��,��,��,��,��,��,��,��,' +
        '��,��,��,��,��,��,��,ԣ,��,ȹ,л,ҥ,ǫ,��,��,��,϶,��,��,��,��,ƭ,Ե,��,��,��,��,��,��,��,��,Я,��,ҡ,��,' + '��,̯,��,��,ȵ,��,Ĺ,Ļ,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,µ,��,��,��,��,��,��,��,˯,��,' + '��,��,ů,��,Ъ,��,��,��,��,��,·,��,ɤ,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,ǩ,��,��,��,ɵ,��,��,' + '΢,��,ң,��,��,��,��,��,̵,��,��,��,��,��,��,��,��,��,ú,��,��,Į,Դ,��,��,��,Ϫ,��,��,��,��,��,��,��,��,' +
        '��,��,��,��,��,��,��,��,��,ǽ,Ʋ,��,��,��,ժ,ˤ,��,��,Ľ,ĺ,��,ģ,��,��,ե,��,��,��,��,��,��,Ը,��,��,��,' + '��,Ӭ,֩,׬,��,��,��,��,��,��,��,��,��,Ĥ,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,Ϩ,��,��,Ư,��,��,' + '��,©,��,կ,��,��,��,��,��,��,��,��,��,��,��,˺,��,Ȥ,��,��,��,��,��,Ь,��,��,��,��,ӣ,��,Ʈ,��,��,��,ù,' + '��,��,��,Ϲ,Ӱ,��,̤,��,��,ī,��,��,��,��,��,��,��,��,ƪ,��,��,��,ϥ,��,��,Ħ,��,��,��,��,Ǳ,��,��,��,ο,' +
        '��,��,��,��,н,��,��,��,��,��,��,��,��,��,Ĭ,��,��,��,��,��,��,��,ĥ,��,��,��,��,��,ȼ,��,��,��,��,��,��,' + '��,˪,ϼ,��,��,��,��,Ӯ,��,��,��,��,��,��,��,��,��,��,��,ӥ,��,��,��,��,��,��,��,��,ҫ,��,��,��,��,ħ,��,' + '��,��,¶,��,��,ר,Ԫ,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,ɡ,��,��,Υ,Զ,ȴ,��,��,��,' + '��,��,��,��,��,Ŭ,��,��,ֱ,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,ʡ,��,��,��,��,��,��,��,��,��,' +
        '��,��,��,��,ɹ,Ц,��,��,��,��,��,��,��,��,Ʊ,��,��,��,��,��,��,��,Խ,��,��,��,��,��,��,��,ɩ,��,��,��,��,' + '��,��,̲,��,��,��,ò,��,��,ײ,��,Ƨ,��,��,��,��,��,ֹ,��,��,��,��,Ȱ,��,��,��,��,��,��,��,��,ͷ,��,֭,��,' + 'ĸ,��,��,ѹ,��,��,��,��,��,��,��,��,ּ,Ѯ,��,��,��,��,��,Т,��,��,��,��,��,��,��,��,��,��,û,��,��,��,��,' + '��,��,��,��,��,��,��,��,��,��,��,��,��,ҹ,��,к,ע,��,��,��,��,פ,��,֯,ĳ,Ų,��,ש,��,��,ſ,η,��,��,��,' +
        '��,��,��,ͤ,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,��,ȭ,ƿ,��,��,��,��,��,��,��,' + '��,��,��,Ұ,��,��,͵,ż,��,��,��,��,��,��,��,��,ɢ,��,��,��,��,��,��,��,��,��,��,��,ǿ,��,¥,��,��,ǲ,��,' + '��,��,��,��,Ⱥ,��,��,��,��,Ǹ,��,��,��,��,��,��,��,��,��,��,��,ô,��,��,��,��,ӭ,��,��,��,��,��,��,��,��,' + '��,��,׷,��,��,��,��,��,��,��,��,��,��,��,��,';
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


