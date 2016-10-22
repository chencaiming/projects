program TDKExtractor;

uses
  Forms,
  MainUnt in 'MainUnt.pas' {frmMain},
  NativeXml in 'F:\Windows\CodeLib\oldlibrary\Pub\NativeXml.pas',
  uThreadPool in 'base\uThreadPool.pas',
  YQAPI in 'base\YQAPI.pas',
  RegExpr in 'base\RegExpr.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
