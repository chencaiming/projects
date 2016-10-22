unit MainUnt;

interface

uses
    Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
    Dialogs, Menus, ComCtrls, StdCtrls, ExtCtrls, bsSkinData, BusinessSkinForm,
    bsSkinTabs, bsSkinCtrls, AddCategoryUnt, EditGameInfoUnt, bsSkinBoxCtrls,
    SmartListView, bsSkinShellCtrls, uThreadPool, IdHTTP, YQAPI, ZLibExGZ,
    IdSSLOpenSSL, Clipbrd, ComObj;

const
    WM_LISTTDK = WM_USER + 100;
    WM_VIEWLOG = WM_USER + 101;

    

type
    TExtractThreadPool = class(TThreadsPool)
    private
    protected
    public
    end;

    TExtractWorkItem = class(TWorkItem)
    private
        FURL: string;
    public
        property URL: string read FURL write FURL;
    end;

type
    TfrmMain = class(TForm)
        bsbsnsknfrm1: TbsBusinessSkinForm;
        bskndt1: TbsSkinData;
        bscmprsdstrdskn1: TbsCompressedStoredSkin;
        bsSkinPageControl1: TbsSkinPageControl;
        bsSkinSaveDialog1: TbsSkinSaveDialog;
        bskntbshtTdk: TbsSkinTabSheet;
        Panel1: TPanel;
        SmartListViewTDK: TSmartListView;
        Panel4: TPanel;
        Panel2: TPanel;
        Panel3: TPanel;
        GroupBox1: TGroupBox;
        mmoUrl: TMemo;
        btnExtract: TbsSkinButton;
    bsSkinButtonExport: TbsSkinButton;
    bsSkinStatusBar1: TbsSkinStatusBar;
    bsSkinGauge2: TbsSkinGauge;
    bsSkinStatusPanel1: TbsSkinStatusPanel;
        procedure FormCreate(Sender: TObject);
        procedure FormDestroy(Sender: TObject);
        procedure mmoUrlEnter(Sender: TObject);
        procedure btnExtractClick(Sender: TObject);
        procedure SmartListViewTDKCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure SmartListViewTDKKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure mmoUrlKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure bsSkinButtonExportClick(Sender: TObject);
    private
    { Private declarations }
        FPool: TExtractThreadPool;
        procedure ExtractProc(Sender: TThreadsPool; WorkItem: TWorkItem; aThread: TProcessorThread);
        procedure ExtractTDK(Urls: TStrings);
        procedure ListTDK(var Msg: TMessage); message WM_LISTTDK;
        procedure ViewLog(var Msg: TMessage); message WM_VIEWLOG;
        procedure DoFinishEvent(Sender: TThreadsPool; EmptyKind: TEmptyKind);
    public
    { Public declarations }

    end;

var
    frmMain: TfrmMain;

implementation

{$R *.dfm}
function StreamToStr(AStream: TStream): string;
begin
    SetLength(Result, AStream.Size);
    AStream.Position := 0;
    AStream.Read(Result[1], AStream.Size);
end;

procedure TfrmMain.ExtractProc(Sender: TThreadsPool; WorkItem: TWorkItem; aThread: TProcessorThread);
var
    Http: TIdHTTP;
    respData, outStream: TMemoryStream;
    ErrMsg: string;
    RespStr: string;
    strHTML: string;
    m: TStrings;
    Title, Keywords, Desc: string;
    LHandler: TIdSSLIOHandlerSocketOpenSSL;
begin
    //处理tdk提取
    SendMessage(Self.Handle, WM_VIEWLOG, Integer(PChar('正在采集:' + TExtractWorkItem(WorkItem).URL)), 0);
    Http := TIdHTTP.Create;
    m := TStringList.Create;
    respData := TMemoryStream.Create;
    outStream := TMemoryStream.Create;
    LHandler := TIdSSLIOHandlerSocketOpenSSL.Create(nil);
    try
        Http.Disconnect;
        Http.Request.UserAgent := 'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/38.0.2125.122 Safari/537.36 SE 2.X MetaSr 1.0';
        Http.Request.Pragma := 'no-cache';
        Http.Request.CacheControl := 'no-cache';
        Http.Request.Connection := 'close';
        try
            Http.HandleRedirects := true;
//            Http.Head(TExtractWorkItem(WorkItem).URL);
//            http.Request.ContentType := 'application/x-www-form-urlencoded';
            http.IOHandler:=LHandler;
            Http.Get(TExtractWorkItem(WorkItem).URL, respData);
            if Http.Response.ContentEncoding = 'gzip' then
            begin
                respData.Position := 0;
                outStream.Position := 0;
                GZDecompressStream(respData, outStream);
                outStream.Position := 0;
                m.LoadFromStream(outStream);
                strHTML := m.Text;
            end
            else
            begin
                respData.Position := 0;
                m.LoadFromStream(respData);
                strHTML := m.Text;
            end;

            if strHTML = '' then
                Exit;
            RespStr := HtmlToGbk(strHTML);
            RespStr := LowerCase(RespStr);
            //提取标题
            Title := GetMatch(RespStr, '<title>(.*)</title>', 1);

            //提取关键字
            Keywords := GetMatch(RespStr, 'meta[^<>]*?name=\"keywords\"[^<>]*?content=\"([^\"]*?)\"');
            if Keywords = '' then
                Keywords := GetMatch(RespStr, 'meta[^<>]*?content=\"([^\"]*?)\"[^<>]*?name=\"keywords\"');

            if Keywords <> '' then
                Keywords := GetMatch(Keywords, 'content=\"([^\"]*?)\"', 1);


            //提取描述
            Desc := GetMatch(RespStr, 'meta[^<>]*?name=\"description\"[^<>]*?content=\"([^\"]*?)\"');
            if Desc = '' then
                Desc := GetMatch(RespStr, 'meta[^<>]*?content=\"([^\"]*?)\"[^<>]*?name=\"description\"');
            if Desc <> '' then
                Desc := GetMatch(Desc, 'content=\"([^\"]*?)\"', 1);

            RespStr := '<url>' + TExtractWorkItem(WorkItem).URL + '</url><title>' + Title +
                        '</title><keywords>' + Keywords + '</keywords><desc>' + Desc + '</desc><remark>成功</remark>';
        except
            on E: Exception do
            begin
                ErrMsg := E.Message;
                RespStr := '<url>' + TExtractWorkItem(WorkItem).URL + '</url><remark>' + ErrMsg + '</remark>';
                SendMessage(Self.Handle, WM_LISTTDK, Integer(PChar(RespStr)), 0);
                exit;
            end;
        end;
        //显示tdk
        SendMessage(Self.Handle, WM_LISTTDK, Integer(PChar(RespStr)), 0);
        Http.Disconnect;
    finally
        LHandler.Free;
        respData.Free;
        outStream.Free;
        m.Free;
        Http.Free;
    end;
end;

procedure TfrmMain.ExtractTDK(Urls: TStrings);
begin

end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
    FPool := TExtractThreadPool.Create(Self);
    FPool.OnProcessRequest := ExtractProc;
    FPool.OnQueueEmpty := DoFinishEvent;
    FPool.ThreadsMin := 50;
    FPool.ThreadsMax := 100;
    FPool.ThreadDeadTimeout := 10000;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
    FPool.Free;
end;

procedure TfrmMain.ListTDK(var Msg: TMessage);
var
    MsgStr: string;
    AListItem: TListItem;
begin
    MsgStr := StrPas(PChar(Msg.WParam));
    AListItem := SmartListViewTDK.Items.Add;
    AListItem.Caption := GetFieldValueByName(MsgStr, 'url');
    AListItem.SubItems.Add(GetFieldValueByName(MsgStr, 'title'));
    AListItem.SubItems.Add(GetFieldValueByName(MsgStr, 'keywords'));
    AListItem.SubItems.Add(GetFieldValueByName(MsgStr, 'desc'));
    AListItem.SubItems.Add(GetFieldValueByName(MsgStr, 'remark'));
    bsSkinGauge2.Value := bsSkinGauge2.Value + 1;
end;

procedure TfrmMain.mmoUrlEnter(Sender: TObject);
begin
    if mmoUrl.Color = clInfoBk then
    begin
        mmoUrl.Clear;
        mmoUrl.Font.Size := 10;
        mmoUrl.ReadOnly := False;
        mmoUrl.Color := clWindow;
    end;
end;

procedure TfrmMain.btnExtractClick(Sender: TObject);
var
    i: Integer;
    AWorkItem: TExtractWorkItem;
begin
    FPool.KillAllThreads;
    SmartListViewTDK.Clear;
    bsSkinGauge2.MaxValue := mmoUrl.Lines.Count;
    bsSkinGauge2.Value := 0;
    for i := 0 to mmoUrl.Lines.Count - 1 do
    begin
        AWorkItem := TExtractWorkItem.Create;
        AWorkItem.URL := mmoUrl.Lines.Strings[i];
        FPool.AddRequest(AWorkItem);
    end;
end;

procedure TfrmMain.SmartListViewTDKCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
begin
    if item.Index mod 2 = 1 then
    begin
        sender.Canvas.Brush.Color := clSkyBlue;
        sender.Canvas.Font.Color:=clblack;
        sender.Canvas.Font.Size := 10;
    end
    else
    begin
        sender.Canvas.Brush.Color := clwhite;
        sender.Canvas.Font.Color:=clblack;
        sender.Canvas.Font.Size := 10;
    end;
end;

procedure TfrmMain.SmartListViewTDKKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
var
    TDKList: TStringList;
    i: Integer;
begin
    if (ssCtrl in Shift) and (Key = ord('A')) then
    begin
        SmartListViewTDK.SelectAll;
    end
    else if (ssCtrl in Shift) and (Key = ord('C')) then
    begin
        if SmartListViewTDK.SelCount = 0 then
            Exit;

        TDKList := TStringList.Create;
        try
            TDKList.Clear;
            for i := 0 to SmartListViewTDK.Items.count - 1 do
            begin
                if SmartListViewTDK.Items[i].Selected then
                    TDKList.Add(SmartListViewTDK.Items[i].Caption + #9 + SmartListViewTDK.Items[i].SubItems.Strings[0] + #9
                    +  SmartListViewTDK.Items[i].SubItems.Strings[1] +  SmartListViewTDK.Items[i].SubItems.Strings[2]
                    +  SmartListViewTDK.Items[i].SubItems.Strings[3]);
            end;
            Clipboard.SetTextBuf(PChar(TDKList.Text));
        finally
            TDKList.Free;
        end;
    end;
end;

procedure TfrmMain.mmoUrlKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
    if (ssCtrl in Shift) and (Key = ord('A')) then
    begin
        mmoUrl.SelectAll;
    end;
end;

procedure TfrmMain.bsSkinButtonExportClick(Sender: TObject);
var
    ExcelApp: Variant;
    dlgSave: TSaveDialog;
    i, j: Integer;
    tmpStrs: TStrings;
    LineStr: string;
begin
    try
        ExcelApp := CreateOleObject('Excel.Application');
        ExcelApp.Visible := False;
    except
        ShowMessage('您系统未安装MS-EXCEL');
        Exit;
    end;

    dlgSave := TSaveDialog.Create(Self);
    try
        dlgSave.DefaultExt := '.xls';
        dlgSave.Filter := 'Excel文件|*.xls';
        dlgSave.Title := '导出到Excel';
        if dlgSave.Execute then
        begin
            tmpStrs := TStringList.Create;
            try
                ExcelApp.WorkBooks.add;
                ExcelApp.WorkSheets[1].Activate;
                ExcelApp.Cells[1, 1].Value := '网址';
                ExcelApp.Cells[1, 2].Value := '标题';
                ExcelApp.Cells[1, 3].Value := '关键字';
                ExcelApp.Cells[1, 4].Value := '描述';
                ExcelApp.Cells[1, 5].Value := '备注';
                for i := 0 to SmartListViewTDK.Items.count - 1 do
                begin
                    ExcelApp.Cells[i + 2, 1].Value := SmartListViewTDK.Items[i].Caption;
                    ExcelApp.Cells[i + 2, 2].Value := SmartListViewTDK.Items[i].SubItems.Strings[0];
                    ExcelApp.Cells[i + 2, 3].Value := SmartListViewTDK.Items[i].SubItems.Strings[1];
                    ExcelApp.Cells[i + 2, 4].Value := SmartListViewTDK.Items[i].SubItems.Strings[2];
                    ExcelApp.Cells[i + 2, 5].Value := SmartListViewTDK.Items[i].SubItems.Strings[3];
                end;
                ExcelApp.WorkSheets[1].SaveAs(dlgSave.FileName);
                ShowMessage('导出完毕！');
            finally
                ExcelApp.WorkBooks.close;
                ExcelApp.quit;
                ExcelApp := Unassigned;
                tmpStrs.Free;
            end;
        end;
    finally
        dlgSave.Free;
    end;
end;

procedure TfrmMain.ViewLog(var Msg: TMessage);
var
    MsgStr: string;
    AListItem: TListItem;
begin
    MsgStr := StrPas(PChar(Msg.WParam));
    bsSkinStatusPanel1.Caption := MsgStr;
end;

procedure TfrmMain.DoFinishEvent(Sender: TThreadsPool;
  EmptyKind: TEmptyKind);
begin
    if EmptyKind = ekProcessingFinished then
        SendMessage(Self.Handle, WM_VIEWLOG, Integer(PChar('完成')), 0);
end;

end.


