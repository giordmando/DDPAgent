unit Flux.Dispatcher;

interface

uses
  Grijjy.System.Messaging,
  System.SyncObjs,
  System.Generics.Collections,
  System.Classes;

type
  IFluxDispatcher = interface
    ['{2F8EF23B-A370-45FE-AA10-AAB7BF6D27F7}']
    procedure &Register(const AMessageClass: TgrMessageClass;
      const AListenerMethod: TgrMessageListenerMethod);
    procedure UnRegister(const AMessageClass: TgrMessageClass;
      const AListenerMethod: TgrMessageListenerMethod);
    // AEvent could be an event (store changed) or an action (user-view interaction)
    procedure DoDispatch(const AEventOrAction: TgrMessage);
  end;

function GetFluxDispatcher: IFluxDispatcher;

implementation

var
  _FluxDispatcher: IFluxDispatcher;

type
  TFluxDispatcher = class(TInterfacedObject, IFluxDispatcher)
  private
    FMsgManager: TgrMessageManager;
    FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    procedure &Register(const AMessageClass: TgrMessageClass;
      const AListenerMethod: TgrMessageListenerMethod);
    procedure UnRegister(const AMessageClass: TgrMessageClass;
      const AListenerMethod: TgrMessageListenerMethod);
    procedure DoDispatch(const AEventOrAction: TgrMessage);
  end;

  { TFluxDispatcher }

constructor TFluxDispatcher.Create;
begin
  inherited Create;
  FMsgManager := TgrMessageManager.Create;
  FLock := TCriticalSection.Create;
end;

destructor TFluxDispatcher.Destroy;
begin
  FLock.Free;
  FMsgManager.Free;
  inherited;
end;

procedure TFluxDispatcher.Register(const AMessageClass: TgrMessageClass;
  const AListenerMethod: TgrMessageListenerMethod);
begin
  FLock.Enter;
  try
    FMsgManager.SubscribeToMessage(AMessageClass, AListenerMethod);
  finally
    FLock.Leave;
  end;
end;

procedure TFluxDispatcher.UnRegister(const AMessageClass: TgrMessageClass;
  const AListenerMethod: TgrMessageListenerMethod);
begin
  FLock.Enter;
  try
    FMsgManager.Unsubscribe(AMessageClass, AListenerMethod);
  finally
    FLock.Leave;
  end;
end;

procedure TFluxDispatcher.DoDispatch(const AEventOrAction: TgrMessage);
begin
  FLock.Enter;
  try
    WriteLn('[DEBUG Dispatcher] DoDispatch from Thread: ');
    if TThread.CurrentThread.ThreadID = MainThreadID then
      FMsgManager.QueueMessage(Self, AEventOrAction)
    else
      FMsgManager.SendMessage(Self, AEventOrAction);
  finally
    FLock.Leave;
  end;
end;


function GetFluxDispatcher: IFluxDispatcher;
begin
  Result := _FluxDispatcher;
end;

initialization

_FluxDispatcher := TFluxDispatcher.Create;

end.
