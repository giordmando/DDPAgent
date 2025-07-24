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

{
TAgentMethodHandler = class(TInterfacedObject, IMethodDataHandler)
  private
    FAgentId: string;
    FCallMethodProc: TCallMethodProc;
    FHandlers: TDictionary<string, TMethodDataHandlerProc>;
    procedure RegisterHandlers;
    function RegisterAgent(const AMethod: string; const Doc: TgrBsonDocument): TgrBsonArray;
    function ping(const AMethod: string; const Doc: TgrBsonDocument): TgrBsonArray;

  protected
    // ICollectionHandler
    function GetMethodName: string;
    function CanHandle(const AMethodType: string): Boolean;
    function HandleAction(const AMethodType: string; const ADoc: TgrBsonDocument): TgrBsonArray;
    function GetHandles: TDictionary<string, TMethodDataHandlerProc>;
  public
    constructor Create(const AAgentId: string; const CallMethodProc: TCallMethodProc);
    destructor Destroy; override;
  end;

TSessionsMethodHandler = class(TInterfacedObject, IMethodDataHandler)
  private
    FAgentId: string;
    FCallMethodProc: TCallMethodProc;
    FHandlers: TDictionary<string, TMethodDataHandlerProc>;
    procedure RegisterHandlers;
    function CloseSession(const AMethod: string; const Doc: TgrBsonDocument): TgrBsonArray;
    function CloseAllSessions(const AMethod: string; const Doc: TgrBsonDocument): TgrBsonArray;
    function SessionHeartbeat(const AMethod: string; const Doc: TgrBsonDocument): TgrBsonArray;
    function SendSessionStatus(const AMethod: string; const Doc: TgrBsonDocument): TgrBsonArray;

  protected
    // ICollectionHandler
    function GetMethodName: string;
    function CanHandle(const AMethodType: string): Boolean;
    function HandleAction(const AMethodType: string; const ADoc: TgrBsonDocument): TgrBsonArray;
    function GetHandles: TDictionary<string, TMethodDataHandlerProc>;
  public
    constructor Create(const AAgentId: string; const CallMethodProc: TCallMethodProc);
    destructor Destroy; override;
  end;


  TCommandMethodHandler = class(TInterfacedObject, IMethodDataHandler)
  private
    FAgentId: string;
    FCallMethodProc: TCallMethodProc;
    FHandlers: TDictionary<string, TMethodDataHandlerProc>;
    procedure RegisterHandlers;

    function SendOutput(const AMethod: string; const Doc: TgrBsonDocument): TgrBsonArray;
    function SendCommandComplete(const AMethod: string; const Doc: TgrBsonDocument): TgrBsonArray;
    function SendError(const AMethod: string; const Doc: TgrBsonDocument): TgrBsonArray;
    function SendCommandExecution(const AMethod: string; const Doc: TgrBsonDocument): TgrBsonArray;

  protected
    // ICollectionHandler
    function GetCollectionName: string;
    function CanHandle(const AMethodType: string): Boolean;
    function HandleAction(const AMethodType: string; const ADoc: TgrBsonDocument): TgrBsonArray;
    function GetHandles: TDictionary<string, TMethodDataHandlerProc>;
  public
    constructor Create(const AAgentId: string; const CallMethodProc: TCallMethodProc);
    destructor Destroy; override;
  end;
  }
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

{TAgentMethodHandler}
{
constructor TAgentMethodHandler.Create(const AAgentId: string; const CallMethodProc: TCallMethodProc);
begin
  inherited Create;
  FAgentId := AAgentId;

  // Inizializza il dizionario e registra gli handler
  FHandlers := TDictionary<string, TMethodDataHandlerProc>.Create;
  FCallMethodProc := CallMethodProc;
  RegisterHandlers;
end;

destructor TAgentMethodHandler.Destroy;
begin
  inherited;
end;

function TAgentMethodHandler.GetCollectionName: string;
begin
  Result := AGENT_COLLECTION;
end;

procedure TAgentMethodHandler.RegisterHandlers;
begin
  // Mappa le costanti ACTION_DDP_... alle rispettive procedure
  FHandlers.Add(AGENT_REGISTER, RegisterAgent);
  FHandlers.Add(TEST_PING, ping);

end;

function TAgentMethodHandler.CanHandle(const AMethodType: string): Boolean;
begin
  // Restituisce true se esiste un handler registrato per AActionType
  Result := FHandlers.ContainsKey(AMethodType);
end;

function TAgentMethodHandler.GetHandles: TDictionary<string, TMethodDataHandlerProc>;
begin
  Result := FHandlers;
end;

function TAgentMethodHandler.HandleAction(const AMethodType: string; const ADoc: TgrBsonDocument): TgrBsonArray;
var
  Handler: TMethodDataHandlerProc;
begin
  if FHandlers.TryGetValue(AMethodType, Handler) then
    Result := Handler(AMethodType, ADoc)
  else
  begin
    Writeln(Format('[SessionHandler] Unhandled action: %s', [AMethodType]));
    Result := TgrBsonArray.Create;
  end;
end;

function TAgentMethodHandler.RegisterAgent(const AMethod: string; const Doc: TgrBsonDocument): TgrBsonArray;
begin
  try
    if not Doc.Contains('session_id') then
      raise Exception.Create('Campo obbligatorio "session_id" mancante.');
    if not Doc.Contains('machine_id') then
      raise Exception.Create('Campo obbligatorio "machine_id" mancante.');

    // 4. Restituisci un array BSON col documento aggiornato
    Result := TgrBsonArray.Create([Doc]);
    if Assigned(FCallMethodProc) then
        FCallMethodProc(AMethod, Result);
    WriteLn('[Data] Agent registered: ' + FAgentId);

    except
      on E: Exception do
        WriteLn('[Data] Error registering agent: ' + E.Message);
    end;
end;

function TAgentMethodHandler.ping(const AMethod: string; const Doc: TgrBsonDocument): TgrBsonArray;
var
  LBsonDoc: TgrBsonDocument;
begin

  try
    LBsonDoc := TgrBsonDocument.Create;
    LBsonDoc['machine_id'] := FAgentId;
    Result := TgrBsonArray.Create([LBsonDoc]);
    if Assigned(FCallMethodProc) then
      FCallMethodProc(AMethod, TgrBsonArray.Create([LBsonDoc]));
  except
      on E: Exception do
        WriteLn('[Data] Error ping agent: ' + E.Message);
    end;

end;
}
{TSessionsMethodHandler}
{
constructor TSessionsMethodHandler.Create(const AAgentId: string; const CallMethodProc: TCallMethodProc);
begin
  inherited Create;
  FAgentId := AAgentId;

  // Inizializza il dizionario e registra gli handler
  FHandlers := TDictionary<string, TMethodDataHandlerProc>.Create;
  FCallMethodProc := CallMethodProc;
  RegisterHandlers;
end;

destructor TSessionsMethodHandler.Destroy;
begin
  inherited;
end;

function TSessionsMethodHandler.GetCollectionName: string;
begin
  Result := AGENT_COLLECTION;
end;

procedure TSessionsMethodHandler.RegisterHandlers;
begin
  // Mappa le costanti ACTION_DDP_... alle rispettive procedure
  FHandlers.Add(SESSION_CLOSE, CloseSession);
  FHandlers.Add(SESSION_CLOSE_ALL, CloseAllSessions);
  FHandlers.Add(SESSION_HEARTBEAT, SessionHeartbeat);
  FHandlers.Add(SESSION_STATUS, SendSessionStatus);

end;

function TSessionsMethodHandler.CanHandle(const AMethodType: string): Boolean;
begin
  // Restituisce true se esiste un handler registrato per AActionType
  Result := FHandlers.ContainsKey(AMethodType);
end;

function TSessionsMethodHandler.GetHandles: TDictionary<string, TMethodDataHandlerProc>;
begin
  Result := FHandlers;
end;

function TSessionsMethodHandler.HandleAction(const AMethodType: string; const ADoc: TgrBsonDocument): TgrBsonArray;
var
  Handler: TMethodDataHandlerProc;
begin
  if FHandlers.TryGetValue(AMethodType, Handler) then
    Result := Handler(AMethodType, ADoc)
  else
  begin
    Writeln(Format('[SessionHandler] Unhandled action: %s', [AMethodType]));
    Result := TgrBsonArray.Create;
  end;
end;


function TSessionsMethodHandler.CloseSession(const AMethod: string; const Doc: TgrBsonDocument): TgrBsonArray;
begin
  try
    if not Doc.Contains('session_id') then
      raise Exception.Create('Campo obbligatorio "session_id" mancante.');
    if not Doc.Contains('machine_id') then
      raise Exception.Create('Campo obbligatorio "machine_id" mancante.');

    // 4. Restituisci un array BSON col documento aggiornato
    Result := TgrBsonArray.Create([Doc]);
    if Assigned(FCallMethodProc) then
        FCallMethodProc(AMethod, Result);
    WriteLn('[Data] Agent registered: ' + FAgentId);

    except
      on E: Exception do
        WriteLn('[Data] Error registering agent: ' + E.Message);
    end;
end;


function TSessionsMethodHandler.CloseAllSessions(const AMethod: string; const Doc: TgrBsonDocument): TgrBsonArray;
var
  LBsonDoc: TgrBsonDocument;
begin

  try
    LBsonDoc := TgrBsonDocument.Create;
    LBsonDoc['machine_id'] := FAgentId;
    Result := TgrBsonArray.Create([LBsonDoc]);
    if Assigned(FCallMethodProc) then
      FCallMethodProc(AMethod, TgrBsonArray.Create([LBsonDoc]));
  except
      on E: Exception do
        WriteLn('[Data] Error ping agent: ' + E.Message);
    end;

end;


function TSessionsMethodHandler.SessionHeartbeat(const AMethod: string; const Doc: TgrBsonDocument): TgrBsonArray;
var
  LBsonDoc: TgrBsonDocument;
begin

  try
    LBsonDoc := TgrBsonDocument.Create;
    LBsonDoc['machine_id'] := FAgentId;
    Result := TgrBsonArray.Create([LBsonDoc]);
    if Assigned(FCallMethodProc) then
      FCallMethodProc(AMethod, TgrBsonArray.Create([LBsonDoc]));
  except
      on E: Exception do
        WriteLn('[Data] Error ping agent: ' + E.Message);
    end;

end;


function TSessionsMethodHandler.SendSessionStatus(const AMethod: string; const Doc: TgrBsonDocument): TgrBsonArray;
var
  LBsonDoc: TgrBsonDocument;
begin

  try
    Result := TgrBsonArray.Create([Doc]);
    if Assigned(FCallMethodProc) then
      FCallMethodProc(AMethod, TgrBsonArray.Create([Doc]));
  except
      on E: Exception do
        WriteLn('[Data] Error ping agent: ' + E.Message);
    end;

end;
}

{TCommandMethodHandler}

{
constructor TCommandMethodHandler.Create(const AAgentId: string; const CallMethodProc: TCallMethodProc);
begin
  inherited Create;
  FAgentId := AAgentId;

  // Inizializza il dizionario e registra gli handler
  FHandlers := TDictionary<string, TMethodDataHandlerProc>.Create;
  FCallMethodProc := CallMethodProc;
  RegisterHandlers;
end;

destructor TCommandMethodHandler.Destroy;
begin
  inherited;
end;

function TCommandMethodHandler.GetCollectionName: string;
begin
  Result := AGENT_COLLECTION;
end;

procedure TCommandMethodHandler.RegisterHandlers;
begin
  // Mappa le costanti ACTION_DDP_... alle rispettive procedure
  FHandlers.Add(COMMAND_OUTPUT, SendOutput);
  FHandlers.Add(COMMAND_COMPLETED, SendCommandComplete);
  FHandlers.Add(COMMAND_SEND_ERROR, SendError);
  FHandlers.Add(COMMAND_EXECUTION, SendCommandExecution);

end;

function TCommandMethodHandler.CanHandle(const AMethodType: string): Boolean;
begin
  // Restituisce true se esiste un handler registrato per AActionType
  Result := FHandlers.ContainsKey(AMethodType);
end;

function TCommandMethodHandler.GetHandles: TDictionary<string, TMethodDataHandlerProc>;
begin
  Result := FHandlers;
end;

function TCommandMethodHandler.HandleAction(const AMethodType: string; const ADoc: TgrBsonDocument): TgrBsonArray;
var
  Handler: TMethodDataHandlerProc;
begin
  if FHandlers.TryGetValue(AMethodType, Handler) then
    Result := Handler(AMethodType, ADoc)
  else
  begin
    Writeln(Format('[CommandMethodHandler] Unhandled action: %s', [AMethodType]));
    Result := TgrBsonArray.Create;
  end;
end;


function TCommandMethodHandler.SendOutput(const AMethod: string; const Doc: TgrBsonDocument): TgrBsonArray;
begin
  try
    if not Doc.Contains('session_id') then
      raise Exception.Create('Campo obbligatorio "session_id" mancante.');
    if not Doc.Contains('machine_id') then
      raise Exception.Create('Campo obbligatorio "machine_id" mancante.');
    if not Doc.Contains('command_id') then
      raise Exception.Create('Campo obbligatorio "command_id" mancante.');

    // 4. Restituisci un array BSON col documento aggiornato
    Result := TgrBsonArray.Create([Doc]);
    if Assigned(FCallMethodProc) then
        FCallMethodProc(AMethod, Result);

    except
      on E: Exception do
        WriteLn('[Data] Error TCommandMethodHandler.SendOutput: ' + E.Message);
    end;
end;


function TCommandMethodHandler.SendCommandComplete(const AMethod: string; const Doc: TgrBsonDocument): TgrBsonArray;
begin
  try
    if not Doc.Contains('exit_code') then
      raise Exception.Create('Campo obbligatorio "exit_code" mancante.');
    if not Doc.Contains('machine_id') then
      raise Exception.Create('Campo obbligatorio "machine_id" mancante.');
    if not Doc.Contains('command_id') then
      raise Exception.Create('Campo obbligatorio "command_id" mancante.');

    // 4. Restituisci un array BSON col documento aggiornato
    Result := TgrBsonArray.Create([Doc]);
    if Assigned(FCallMethodProc) then
        FCallMethodProc(AMethod, Result);

  except
      on E: Exception do
        WriteLn('[Data] TCommandMethodHandler.SendCommandComplete: ' + E.Message);
    end;
end;


function TCommandMethodHandler.SendError(const AMethod: string; const Doc: TgrBsonDocument): TgrBsonArray;
var
  LBsonDoc: TgrBsonDocument;
begin

  try
    if not Doc.Contains('session_id') then
      raise Exception.Create('Campo obbligatorio "session_id" mancante.');
    if not Doc.Contains('machine_id') then
      raise Exception.Create('Campo obbligatorio "machine_id" mancante.');
    if not Doc.Contains('error') then
      raise Exception.Create('Campo obbligatorio "error" mancante.');

    // 4. Restituisci un array BSON col documento aggiornato
    Result := TgrBsonArray.Create([Doc]);
    if Assigned(FCallMethodProc) then
        FCallMethodProc(AMethod, Result);
  except
      on E: Exception do
        WriteLn('[Data] Error TCommandMethodHandler.SendError: ' + E.Message);
    end;

end;


function TCommandMethodHandler.SendCommandExecution(const AMethod: string; const Doc: TgrBsonDocument): TgrBsonArray;
var
  LBsonDoc: TgrBsonDocument;
begin

  try
    if not Doc.Contains('command_id') then
      raise Exception.Create('Campo obbligatorio "command_id" mancante.');

    Result := TgrBsonArray.Create([Doc]);
    if Assigned(FCallMethodProc) then
      FCallMethodProc(AMethod, TgrBsonArray.Create([Doc]));
  except
      on E: Exception do
        WriteLn('[Data] Error CommandMethodHandler.SendCommandExecution: ' + E.Message);
    end;

end;
}

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

    ADDPClient.Subscribe(FSubscriptionName,//Example COMMANDS_SUBSCRIPTION,
      TgrBsonArray.Create([
        //Example TgrBsonDocument.Create.Add('machine_id', Doc['machine_id'])
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
