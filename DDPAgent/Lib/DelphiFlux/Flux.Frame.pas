unit Flux.Frame;

interface

uses
  Flux.Dispatcher,
  Grijjy.System.Messaging,
  FMX.Forms,
  System.Classes,
  System.Generics.Collections,
  System.SyncObjs;

type
  TFluxFrame = class(TFrame)
  private
    FDispatcher: IFluxDispatcher;
    FDispatcherSubscriptions: TDictionary<TgrMessageClass, TgrMessageListenerMethod>;
    FLock: TCriticalSection;
  protected
    procedure InitializeFluxDependencies; virtual;
    procedure RegisterToDispatcherMsg(const AMessageClass: TgrMessageClass;
      const AListenerMethod: TgrMessageListenerMethod);
    procedure UpdateView; virtual; abstract;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

implementation

{ TFluxFrame }

constructor TFluxFrame.Create(AOwner: TComponent);
begin
  inherited;
  FLock := TCriticalSection.Create;
  FDispatcherSubscriptions := TDictionary<TgrMessageClass, TgrMessageListenerMethod>.Create;
  InitializeFluxDependencies;
  UpdateView;
end;

destructor TFluxFrame.Destroy;
begin
  FLock.Enter;
  try
    for var LSubscription in FDispatcherSubscriptions do
    begin
      FDispatcher.UnRegister(LSubscription.Key, LSubscription.Value);
    end;
    FDispatcherSubscriptions.Free;
  finally
    FLock.Leave;
  end;

  FLock.Free;
  inherited;
end;

procedure TFluxFrame.InitializeFluxDependencies;
begin
  FDispatcher := GetFluxDispatcher();
end;

procedure TFluxFrame.RegisterToDispatcherMsg(const AMessageClass: TgrMessageClass;
  const AListenerMethod: TgrMessageListenerMethod);
begin
  FLock.Enter;
  try
    if not FDispatcherSubscriptions.ContainsKey(AMessageClass) then
    begin
      FDispatcher.Register(AMessageClass, AListenerMethod);
      FDispatcherSubscriptions.Add(AMessageClass, AListenerMethod);
    end;
  finally
    FLock.Leave;
  end;
end;

end.
