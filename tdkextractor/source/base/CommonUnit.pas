unit CommonUnit;

interface
uses
  Classes, SysUtils, ZLib, Windows, EncdDecd;

const
  cKey1 = 52845;
  cKey2 = 22719;
  cKey = 'hisenbo';
  
procedure ys_stream(instream, outStream: TStream; ysbz: integer);
procedure jy_Stream(instream, outStream: TStream);

function NewEncrypt(ACount: Integer): string; //�ֶμ���
function NewDeEncrypt(AStr: string): integer; //�ֶν���

function  Decrypt(const S: string): string;
function  Encrypt(const S: string): string;


implementation

procedure ys_stream(instream, outStream: TStream; ysbz: integer);
{
instream�� ��ѹ�����Ѽ����ļ���
outStream  ѹ��������ļ���
ysbz:ѹ����׼
}
var
  ys: TCompressionStream;
begin
 //��ָ��ָ��ͷ��
  inStream.Position := 0;
 //ѹ����׼��ѡ��
  case ysbz of
    1: ys := TCompressionStream.Create(clnone, OutStream); //��ѹ��
    2: ys := TCompressionStream.Create(clFastest, OutStream); //����ѹ��
    3: ys := TCompressionStream.Create(cldefault, OutStream); //��׼ѹ��
    4: ys := TCompressionStream.Create(clmax, OutStream); //���ѹ��
  else

    ys := TCompressionStream.Create(clFastest, OutStream);
  end;

  try
   //ѹ����
    ys.CopyFrom(inStream, 0);
  finally
    ys.Free;
  end;
end;

//*****************************************************************


//����ѹ

procedure jy_Stream(instream, outStream: TStream);
{
instream :ԭѹ�����ļ�
outStream����ѹ�����ļ�
}
var
  jyl: TDeCompressionStream;
  buf: array[1..512] of byte;
  sjread: integer;
begin
  inStream.Position := 0;
  jyl := TDeCompressionStream.Create(inStream);
  try
    repeat
     //����ʵ�ʴ�С
      sjRead := jyl.Read(buf, sizeof(buf));
      if sjread > 0 then
        OutStream.Write(buf, sjRead);
    until (sjRead = 0);
  finally
    jyl.Free;
  end;
end;


//Decrypt a string encoded with Encrypt
function Decrypt(const S: string): string;
var
  EncryptStr: string;
  StartPos: Integer;
begin
  EncryptStr := NewEncrypt(258);
  StartPos := Length(EncryptStr) + 1;
  Result := DecodeString(Copy(S, StartPos, Length(S)));
end;

//Encrypt a string
function Encrypt(const S: string): string;
begin
 Result := NewEncrypt(258) + EncodeString(S);
end;



function NewEncrypt(ACount: Integer): string;
begin
  Result := EncodeString(EncodeString(IntToStr(ACount)) + ckey);
end;

function NewDeEncrypt(AStr: string): Integer;
begin
  if AStr = '' then
    Result := 0
  else
    Result := StrToIntDef(DecodeString(StringReplace(DecodeString(Astr), cKey, '', [rfReplaceAll])), 0);
end;

end.