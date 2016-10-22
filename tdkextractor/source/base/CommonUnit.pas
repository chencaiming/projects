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

function NewEncrypt(ACount: Integer): string; //字段加密
function NewDeEncrypt(AStr: string): integer; //字段解密

function  Decrypt(const S: string): string;
function  Encrypt(const S: string): string;


implementation

procedure ys_stream(instream, outStream: TStream; ysbz: integer);
{
instream： 待压缩的已加密文件流
outStream  压缩后输出文件流
ysbz:压缩标准
}
var
  ys: TCompressionStream;
begin
 //流指针指向头部
  inStream.Position := 0;
 //压缩标准的选择
  case ysbz of
    1: ys := TCompressionStream.Create(clnone, OutStream); //不压缩
    2: ys := TCompressionStream.Create(clFastest, OutStream); //快速压缩
    3: ys := TCompressionStream.Create(cldefault, OutStream); //标准压缩
    4: ys := TCompressionStream.Create(clmax, OutStream); //最大压缩
  else

    ys := TCompressionStream.Create(clFastest, OutStream);
  end;

  try
   //压缩流
    ys.CopyFrom(inStream, 0);
  finally
    ys.Free;
  end;
end;

//*****************************************************************


//流解压

procedure jy_Stream(instream, outStream: TStream);
{
instream :原压缩流文件
outStream：解压后流文件
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
     //读入实际大小
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
