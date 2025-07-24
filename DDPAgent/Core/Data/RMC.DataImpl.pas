unit RMC.DataImpl;

interface
uses
  RMC.DataInterface,
  DDP.Interfaces,
  Grijjy.Data.Bson,
  System.Generics.Collections,
  System.SysUtils,
  System.DateUtils,
  RMC.Actions.Consts,
  System.SyncObjs,
  AgentServiceI;

const

  SESSION_COLLECTION='sessions';
  AGENT_COLLECTION='agents';

type

THandleSubscribe = class(TInterfacedObject, ISubscriptionCollection)
  private
    FDDPClient: IDDPClient;
    FSubscriptionName:string;
    FParams: TgrBsonDocument;
  public
    procedure Subscribe(const ADDPClient: IDDPClient);
    function GetSubscriptionName: string;
    procedure SetSubscriptionName(const SubscriptionName: string);
    property SubscriptionName: string
      read GetSubscriptionName write SetSubscriptionName;
    constructor Create(const SubscriptionName: string; const Params: TgrBsonDocument);
    destructor Destroy; override;
end;

TSubscriptionRegistry = class(TInterfacedObject, ISubscriptionRegistry)
  private
    FCollections: TList<ISubscriptionCollection>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RegisterCollection(const Collection: ISubscriptionCollection);
    procedure SubscribeAll(const ADDPClient:IDDPClient);
  end;

TMethodDispatcher = class(TInterfacedObject, IMethodDispatcher)
  private
    FHandlers: TDictionary<string, TMethodDataHandlerProc>;
  protected
    procedure RegisterHandler(const AHandler: IMethodDataHandler);
    procedure UnregisterHandler(const AMethodName: string);
    procedure DispatchMethod(const AMethodName: string; const ADoc: TgrBsonDocument);
  public
    constructor Create;
    destructor Destroy; override;
  end;

TMethodHandlerFactory = class(TInterfacedObject, IMethodHandlerFactory)
  private
   FApplicationFactories: TDictionary<string, IApplicationMethodFactory>;
   FLock: TCriticalSection;

  protected
    // IMethodHandlerFactory implementation
    function CreateHandlers(const AgentId: string; const AgentData: IAgentData;
    const CallMethodProc: TCallMethodProc): TArray<IMethodDataHandler>;

    // Registration methods
    procedure RegisterApplicationFactory(const AFactory: IApplicationMethodFactory);
    procedure UnregisterApplicationFactory(const AApplicationName: string);
    function GetRegisteredApplications: TArray<string>;

  public
    constructor Create;

  end;

function GetSubscriptionRegistry: ISubscriptionRegistry;
function GetMethodHandlerFactory: IMethodHandlerFactory;

implementation

var
  _SubscriptionRegistry:ISubscriptionRegistry;
  _MethodHandlerFactory:IMethodHandlerFactory;

const

  // Agent methods
  AGENT_REGISTER = 'agent.register';

  // Subscriptions
  SESSIONS_SUBSCRIPTION = 'agent.sessions';
  COMMANDS_SUBSCRIPTION = 'agent.commands';

  // Session methods
  SESSION_CLOSE = 'sessions.close';
  SESSION_CLOSE_ALL = 'sessions.closeAll';
  SESSION_HEARTBEAT = 'sessions.heartbeat';
  SESSION_STATUS = 'session.sessionStatus';

{THandleSubscribe}
constructor THandleSubscribe.Create(const SubscriptionName: string; const Params: TgrBsonDocument);
begin
  FSubscriptionName:= SubscriptionName;
  FParams:=Params;
end;

destructor THandleSubscribe.Destroy;
begin
end;

procedure THandleSubscribe.SetSubscriptionName(const SubscriptionName: string);
 begin
    FSubscriptionName := SubscriptionName;
 end;

function THandleSubscribe.GetSubscriptionName;
 begin
  Result := FSubscriptionName;
 end;

procedure THandleSubscribe.Subscribe(const ADDPClient: IDDPClient);
begin
  try
    if not FParams.Contains('machine_id') then
      raise Exception.Create('Campo obbligatorio "machine_id" mancante.');

    ADDPClient.Subscribe(FSubscriptionName,
      TgrBsonArray.Create([
        FParams
      ]));
    WriteLn('[Data] Subscribed to commands for agent: ' + FParams['machine_id']);
  except
    on E: Exception do
      WriteLn('[Data] Error subscribing to commands: ' + E.Message);
  end;
end;


{TSubscriptionRegistry}
constructor TSubscriptionRegistry.Create;
begin
  inherited;
  FCollections := TList<ISubscriptionCollection>.Create;
end;

destructor TSubscriptionRegistry.Destroy;
begin
  FCollections.Free;
  inherited;
end;

procedure TSubscriptionRegistry.RegisterCollection(const Collection: ISubscriptionCollection);
begin
  if Assigned(Collection) and (FCollections.IndexOf(Collection) < 0) then
    FCollections.Add(Collection);
end;

procedure TSubscriptionRegistry.SubscribeAll(const ADDPClient:IDDPClient);
var
  Sub: ISubscriptionCollection;
begin
  for Sub in FCollections do
    Sub.Subscribe(ADDPClient);
end;

{TMethodDispatcher}
constructor TMethodDispatcher.Create;
begin
  inherited;
  FHandlers := TDictionary<string, TMethodDataHandlerProc>.Create;
end;

destructor TMethodDispatcher.Destroy;
begin
  FHandlers.Free;
  inherited;
end;

procedure TMethodDispatcher.RegisterHandler(const AHandler: IMethodDataHandler);
var
  MethodName: string;
begin
  if Assigned(AHandler) then
    for MethodName in AHandler.GetHandles.Keys do
    begin
      if FHandlers.ContainsKey(MethodName) then
        raise Exception.CreateFmt('Duplicato: metodo già registrato (%s)', [MethodName]);
      FHandlers.Add(MethodName, AHandler.GetHandles[MethodName]);
    end;
end;


procedure TMethodDispatcher.UnregisterHandler(const AMethodName: string);
begin
  FHandlers.Remove(AMethodName);
end;

procedure TMethodDispatcher.DispatchMethod(const AMethodName: string; const ADoc: TgrBsonDocument);
var
  Handler: TMethodDataHandlerProc;
begin

  if FHandlers.TryGetValue(AMethodName, Handler) then
  begin
    Handler(AMethodName, ADoc);
  end
  else
    WriteLn(Format('[MethodDispatcher] No handler registered for Method Name: %s', [AMethodName]));
end;

function GetSubscriptionRegistry;
begin;
  Result:= _SubscriptionRegistry
end;

{TMethodHandlerFactory}

constructor TMethodHandlerFactory.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FApplicationFactories:= TDictionary<string, IApplicationMethodFactory>.Create;
end;

function TMethodHandlerFactory.CreateHandlers(const AgentId: string; const AgentData: IAgentData;
 const CallMethodProc: TCallMethodProc): TArray<IMethodDataHandler>;
var
  AllHandlers: TList<IMethodDataHandler>;
  AppFactory: IApplicationMethodFactory;
  AppHandlers: TArray<IMethodDataHandler>;
  Handler: IMethodDataHandler;
  i: Integer;
begin
  FLock.Enter;
  try
    AllHandlers := TList<IMethodDataHandler>.Create;
    try
      // AUTOMATIC: Aggregate handlers from all registered application factories
      for AppFactory in FApplicationFactories.Values do
      begin
        WriteLn(Format('[Core] Creating method handlers for application: %s', [AppFactory.GetApplicationName]));

        AppHandlers := AppFactory.CreateHandlers(AgentId, AgentData, CallMethodProc);
        for Handler in AppHandlers do
          AllHandlers.Add(Handler);
      end;

      // Convert to array
      SetLength(Result, AllHandlers.Count);
      for i := 0 to AllHandlers.Count - 1 do
        Result[i] := AllHandlers[i];

      WriteLn(Format('[Core] Created %d total method handlers from %d applications',
        [Length(Result), FApplicationFactories.Count]));

    finally
      AllHandlers.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TMethodHandlerFactory.RegisterApplicationFactory(const AFactory: IApplicationMethodFactory);
begin
  FLock.Enter;
  try
    FApplicationFactories.AddOrSetValue(AFactory.GetApplicationName, AFactory);
    WriteLn(Format('[Core] Registered method factory for application: %s', [AFactory.GetApplicationName]));
  finally
    FLock.Leave;
  end;
end;

procedure TMethodHandlerFactory.UnregisterApplicationFactory(const AApplicationName: string);
begin
  FLock.Enter;
  try

    if FApplicationFactories.ContainsKey(AApplicationName) then
    begin
      FApplicationFactories.Remove(AApplicationName);
      WriteLn(Format('[Core] Unregistered method factory for application: %s', [AApplicationName]));
    end;

  finally
    FLock.Leave;
  end;
end;

function TMethodHandlerFactory.GetRegisteredApplications: TArray<string>;
begin
  FLock.Enter;
  try
    Result := FApplicationFactories.Keys.ToArray;
  finally
    FLock.Leave;
  end;
end;

function GetMethodHandlerFactory;
begin;
   if not Assigned(_MethodHandlerFactory) then
    _MethodHandlerFactory := TMethodHandlerFactory.Create;
  Result := _MethodHandlerFactory;
end;

initialization
 begin
  _MethodHandlerFactory := TMethodHandlerFactory.Create;
  _SubscriptionRegistry := TSubscriptionRegistry.Create;
 end;
end.
