unit Base_Thread;

interface

uses
  Classes, Windows, SysUtils;

type
  // 线程内部专用列表类
  TBaseThreadList = class(TList)
  private
    FLock: TRTLCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    procedure LockList;
    procedure UnlockList;
  end;



implementation

{TBaseThreadList}

constructor TBaseThreadList.Create;
begin
  inherited Create;
  InitializeCriticalSection(FLock);
end;

destructor TBaseThreadList.Destroy;
begin
  try
  LockList;
  try
    inherited Destroy;
  finally
    UnlockList;
    DeleteCriticalSection(FLock);
  end;
  except
    on E:Exception do

  end;
end;

procedure TBaseThreadList.LockList;
begin
  EnterCriticalSection(FLock);
end;

procedure TBaseThreadList.UnlockList;
begin
  if FLock.OwningThread > 0 then
    LeaveCriticalSection(FLock);
end;




end.

