unit RMC.ActionCreator;

interface

uses
  Grijjy.Data.Bson,
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.JSON,
  AgentServiceI,
  RMC.Store.Agent,
  RMC.Connection,
  RMC.Data,
  RMC.DataImpl,
  RMC.DataInterface,
  RMC.ShellServiceFactory,
  RMCAgent.Config,
  RMC.Actions.Consts,
  System.DateUtils,
  Shell.Interfaces;

type

  IActionCreatorAgent = interface

    // Eventi di connessione
    procedure OnDisconnect(const ACode: Integer);
    procedure OnError(const AError: string);
    procedure OnException(const AClassName, AMessage: string);

    procedure Login(const AUsername, APassword: string); overload;
    procedure Login(const AToken: string); overload;
    procedure Login(const AUsername, APassword, A2FACode: string); overload;
    procedure Logout;
    procedure Subscribe;

    procedure RegisterAgent;
    procedure SetServices;

    procedure ping(const ASessionId: string);

    procedure SetAgentConnection(const AgentConnection: IAgentConnection);
    function GetRMCAgentData:IAgentData;

    procedure SetAgentId(const AgentId: string);

    // *** AGGIUNGI QUESTI METODI PER I TEST ***
    function TestInsertSession: string;
    function TestInsertCommand(const ASessionId: string): string;
    function IsConnected: Boolean;
    function GetConnectionStatus: string;

  end;

  // Factory per ottenere l'ActionCreator per un agent specifico
function GetActionCreatorAgent: IActionCreatorAgent;

implementation

uses
  Flux.Actions,
  Flux.ActionCreator.Base,
  System.Generics.Collections,
  BCrypt,
  DDP.Actions.Consts,
  DDP.Factories,
  DDP.Interfaces,
  DDP.NetLib.Factory,
  DDP.RequestGenerator,
  DDP.Exception,
  Nanosystems.Logging,
  Flux.Dispatcher;

type
  TActionCreatorAgent = class(TActionCreatorBase, IActionCreatorAgent)
  private
    FAgentId: string;
    FLock: TCriticalSection;
    FDDPRequestGenerator: IDDPRequestGenerator;
    FAgentConnection: IAgentConnection;
    FAgentData: IAgentData;
    FAutoReconnect: Boolean;
    FToken: string;
    FShellSessionService: IShellSessionService;
    //FShellRunnerFactory: IShellRunnerFactory;

    FDDPNetLib: IDDPNetLib; // <- Mantieni riferimento
    FDDPClient: IDDPClient; // <- Mantieni riferimento
    FDDPLogin: IDDPLogin;
    FDDPSessionId: string;
    FAgentStore: IStoreAgent;
    function GetAutoReconnect: Boolean;
    function GetToken: string;
    procedure SetAutoReconnect(const AValue: Boolean);
    procedure SetToken(const AValue: string);
    procedure Build;
    function DDPConnect: Boolean;
    procedure DDPDisconnect;
    function DDPLogin(const AUsername, APassword: string): Boolean; overload;
    function DDPLogin(const AToken: string): Boolean; overload;
    function DDPLogin(const AUsername, APassword, A2FACode: string)
      : Boolean; overload;
    procedure DDPLogout;
    procedure DDPSubscribe;
    procedure StartAutoReconnect;
  protected
    { IActionCreatorAgent implementation }

    procedure OnDisconnect(const ACode: Integer);
    procedure OnError(const AError: string);
    procedure OnException(const AClassName, AMessage: string);

    procedure Login(const AUsername, APassword: string); overload;
    procedure Login(const AToken: string); overload;
    procedure Login(const AUsername, APassword, A2FACode: string); overload;
    procedure Logout;
    procedure RegisterAgent;
    procedure SetServices;

    procedure SetAgentConnection(const AgentConnection: IAgentConnection);
    function GetRMCAgentData: IAgentData;
    procedure SetAgentId(const AgentId: string);

    function IsConnected: Boolean;
    function GetConnectionStatus: string;
    procedure Subscribe;

    // *** AGGIUNGI QUESTI METODI PER I TEST ***
    function TestInsertSession: string;
    function TestInsertCommand(const ASessionId: string): string;
    procedure ping(const ASessionId: string);

  public
    constructor Create;
  end;

var

  _Lock: TCriticalSection;
  _ActionCreatorRMCAgent: IActionCreatorAgent;

  { TActionCreatorAgent }

constructor TActionCreatorAgent.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FDDPRequestGenerator := TDDPRequestGenerator.Create;
end;

procedure TActionCreatorAgent.SetAgentConnection(const AgentConnection
  : IAgentConnection);
begin
  FAgentConnection := AgentConnection;
end;

// TODO probabilmente può essere recuperato da qualche singleton non serve impostalo.
procedure TActionCreatorAgent.SetAgentId(const AgentId: string);
begin
  FAgentId := AgentId;
end;

function TActionCreatorAgent.GetRMCAgentData;
begin
  Result := FAgentData;
end;

function TActionCreatorAgent.TestInsertSession: string;
begin
  Result := '';
  try
    if Assigned(FAgentData) then
    begin
      WriteLn('[ActionCreator] Inserting test session...');
      Result := FAgentData.TestInsertSessionForAgent(FAgentId, FDDPSessionId);
      WriteLn('[ActionCreator] Test session inserted: ' + Result);
    end
    else
    begin
      WriteLn('[ActionCreator] Error: FAgentData not assigned');
    end;
  except
    on E: Exception do
      WriteLn('[ActionCreator] Error inserting test session: ' + E.Message);
  end;
end;

function TActionCreatorAgent.TestInsertCommand(const ASessionId
  : string): string;
begin
  Result := '';
  try
    if Assigned(FAgentData) then
    begin
      WriteLn('[ActionCreator] Inserting test command...');
      Result := FAgentData.TestInsertCommandForAgent(FAgentId, ASessionId,
        'ping www.google.com');
      WriteLn('[ActionCreator] Test command inserted: ' + Result);
    end
    else
    begin
      WriteLn('[ActionCreator] Error: FAgentData not assigned');
    end;
  except
    on E: Exception do
      WriteLn('[ActionCreator] Error inserting test command: ' + E.Message);
  end;
end;

function TActionCreatorAgent.IsConnected: Boolean;
begin
  Result := Assigned(FAgentConnection) and Assigned(FAgentData);
end;

function TActionCreatorAgent.GetConnectionStatus: string;
begin
  if Assigned(FAgentConnection) and Assigned(FAgentData) then
    Result := 'Connected and ready'
  else if Assigned(FAgentConnection) then
    Result := 'Connected but data not ready'
  else
    Result := 'Not connected';
end;

function TActionCreatorAgent.GetAutoReconnect: Boolean;
begin
  FLock.Enter;
  try
    Result := FAutoReconnect;
  finally
    FLock.Leave;
  end;
end;

function TActionCreatorAgent.GetToken: string;
begin
  FLock.Enter;
  try
    Result := FToken;
  finally
    FLock.Leave;
  end;
end;

procedure TActionCreatorAgent.SetAutoReconnect(const AValue: Boolean);
begin
  FLock.Enter;
  try
    FAutoReconnect := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TActionCreatorAgent.SetToken(const AValue: string);
begin
  FLock.Enter;
  try
    FToken := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TActionCreatorAgent.Build;

begin
  WriteLn('[DEBUG] Building ActionCreator...');
  WriteLn('[DEBUG] Dispatcher ID: ' + IntToHex(Integer(FDispatcher), 8));

  FAgentStore := GetStoreAgent;
  // Verifica che abbiano lo stesso dispatcher
  if Assigned(FAgentStore) then
    WriteLn('[DEBUG] Store created successfully');

  FAgentData := nil;
  FAgentConnection := nil;
  FDDPNetLib := TDDPNetLibFactory.CreateNew;

  FDDPClient := GetDDPClient(FDDPNetLib, FDDPRequestGenerator);
  FDDPLogin := GetDDPLogin(FDDPClient);
  FAgentConnection := GetAgentConnection(FDDPClient, FDDPLogin);
  FAgentData := GetAgentData(FDDPClient);
  FAgentData.SetAgentId(FAgentId);

  SetServices;
end;

function TActionCreatorAgent.DDPConnect: Boolean;
begin
  Result := False;
  FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_CONNECTING));
  try
    FDDPSessionId := FAgentConnection.Connect;
    FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_CONNECTED));
    Result := True;
  except
    on Ex: Exception do
    begin
      FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_CONNECTION_EXCEPTION,
        TgrBsonDocument.Create('name', Ex.ClassName).Add('msg', Ex.Message)));
    end;
  end;
end;

procedure TActionCreatorAgent.DDPDisconnect;
begin
  FAgentConnection.Disconnect;
  FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_DISCONNECTED));
end;

function TActionCreatorAgent.DDPLogin(const AUsername,
  APassword: string): Boolean;
var
  LToken: string;
begin
  Result := False;
  FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_LOGGING_IN));
  try
    LToken := FAgentConnection.Login(AUsername, APassword);
    SetToken(LToken); // save as field for autoreconnect
    FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_LOGGED_IN,
      TgrBsonDocument.Create('token', LToken)));
    FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_USING_TOKEN));
    // now we have the token
    Result := True;
  except
    on E: ELockedLoginException do
    begin
      FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_LOGIN_LOCKED_LOGIN,
        TgrBsonDocument.Create('seconds', E.Seconds)));
    end;
    on E: E2FAuthenticationRequired do
    begin
      // FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_LOGIN_ERROR));
      FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_LOGIN_2FA_REQUIRED));
    end;
    on Ex: Exception do
    begin
      FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_LOGIN_ERROR));
    end;
  end;
end;

function TActionCreatorAgent.DDPLogin(const AToken: string): Boolean;
begin
  Result := False;
  FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_LOGGING_IN));
  try
    FAgentConnection.Login(AToken);
    FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_LOGGED_IN));
    Result := True;
  except
    on Ex: Exception do
    begin
      FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_LOGIN_ERROR));
    end;
  end;
end;

function TActionCreatorAgent.DDPLogin(const AUsername, APassword,
  A2FACode: string): Boolean;
var
  LToken: string;
begin
  Result := False;
  FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_LOGGING_IN));
  try
    LToken := FAgentConnection.Login(AUsername, APassword, A2FACode);
    SetToken(LToken); // save as field for autoreconnect
    FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_LOGGED_IN,
      TgrBsonDocument.Create('token', LToken)));
    FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_USING_TOKEN));
    // now we have the token
    Result := True;
  except
    on Ex: Exception do
    begin
      FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_LOGIN_ERROR));
    end;
  end;
end;

procedure TActionCreatorAgent.DDPLogout;
begin
  FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_LOGGING_OUT));
  FAgentConnection.Logout;
  FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_LOGGED_OUT));
end;

procedure TActionCreatorAgent.DDPSubscribe;
begin
  FDispatcher.DoDispatch(TFluxAction.Create(ACTION_AGENT_SUBSCRIBING));
  try
    FAgentData.SubscribeToCollections;
    FDispatcher.DoDispatch(TFluxAction.Create(ACTION_AGENT_SUBSCRIBED));
  except
    on Ex: Exception do
    begin
      FDispatcher.DoDispatch(TFluxAction.Create(ACTION_AGENT_SUBSCRIBE_ERROR));
    end;
  end;
end;

procedure TActionCreatorAgent.StartAutoReconnect;
var
  LToken: string;
begin
  FLock.Enter;
  try
    if GetAutoReconnect then
      Exit;

    LToken := GetToken;
    if LToken <> '' then
    begin
      SetAutoReconnect(True);
      DoInBackground(
      procedure
      begin
      Sleep(10000);
      FLock.Enter;
      try
        if not GetAutoReconnect then
          Exit;
        SetAutoReconnect(False);
      finally
        FLock.Leave;
      end;
      Log.Info('Reconnecting to RMC', TAG_CLIENT);
      Login(LToken);
       end);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TActionCreatorAgent.Login(const AUsername, APassword: string);
var
  LUsername: string;
  LPassword: string;
begin
  Log.Info('Logging in to RMC using username and password (%s)', [AUsername],
    TAG_CLIENT);

  LUsername := AUsername;
  LPassword := APassword;
  DoInBackground(
    procedure
    begin
      Build;
      FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_USING_CREDENTIALS));
      if not DDPConnect then
        Exit;
      if not DDPLogin(LUsername, LPassword) then
      begin
        DDPDisconnect;
        Exit;
      end;
      { TODO -oAC -cGeneral : handle subscription loading/error }
      Subscribe;
    end);
end;

procedure TActionCreatorAgent.Login(const AToken: string);
var
  LToken: string;
begin
  Log.Info('Logging in to RMC using token', TAG_CLIENT);

  SetAutoReconnect(False);
  SetToken(AToken); // save as field for autoreconnect

  LToken := AToken;
  // DoInBackground(
  // procedure
  // begin
  Build;
  FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_USING_TOKEN));
  if not DDPConnect then
    Exit;
  if not DDPLogin(LToken) then
  begin
    DDPDisconnect;
    Exit;
  end;
  { TODO -oAC -cGeneral : handle subscription loading/error }
  Subscribe;
  // end);
end;

procedure TActionCreatorAgent.Login(const AUsername, APassword,
  A2FACode: string);
var
  LUsername: string;
  LPassword: string;
begin
  Log.Info('Logging in to RMC using 2-Step verification (%s)', [AUsername],
    TAG_CLIENT);

  LUsername := AUsername;
  LPassword := APassword;
  DoInBackground(
    procedure
    begin
      Build;
      FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_USING_CREDENTIALS));
      if not DDPConnect then
        Exit;
      if not DDPLogin(LUsername, LPassword, A2FACode) then
      begin
        DDPDisconnect;
        Exit;
      end;
      { TODO -oAC -cGeneral : handle subscription loading/error }
      Subscribe;
    end);
end;

procedure TActionCreatorAgent.Logout;
var
  LToken: string;
begin
  Log.Info('Logging out from RMC', TAG_CLIENT);

  LToken := GetToken;

  DoInBackground(
    procedure
    begin
      DDPLogout;
      DDPDisconnect;
      FAgentData := nil;
      FAgentConnection := nil;

      SetToken('');
    end);
end;

procedure TActionCreatorAgent.Subscribe;
begin
  try
    RegisterAgent;
    DDPSubscribe;
  finally

  end;
end;

procedure TActionCreatorAgent.RegisterAgent;
begin
  FDispatcher.DoDispatch(TFluxAction.Create(ACTION_AGENT_REGISTERING));
  try
    if Assigned(FAgentConnection) then
    begin
      FAgentData.OnMethod(AGENT_REGISTER, TgrBsonDocument.Create
            .Add('machine_id', FAgentId)
            .Add('session_id', FDDPSessionId)
            .Add('registered_at', DateToISO8601(Now, True)
            ));
      FDispatcher.DoDispatch(TFluxAction.Create(ACTION_AGENT_REGISTERED));
    end
    else
    begin
      FDispatcher.DoDispatch(TFluxAction.Create(ACTION_AGENT_REGISTER_ERROR));
    end;
  except
    on Ex: Exception do
    begin
      FDispatcher.DoDispatch(TFluxAction.Create(ACTION_AGENT_REGISTER_ERROR));
    end;
  end;
end;

procedure TActionCreatorAgent.ping(const ASessionId: string);
begin
 DoInBackground(
    procedure
    begin
      while not TThread.CheckTerminated and IsConnected do
      begin
        FDispatcher.DoDispatch(TFluxAction.Create(TEST_PING));
        Sleep(60000); // 60 secondi
      end;
    end);
end;


procedure TActionCreatorAgent.SetServices;

begin

  FAgentStore.SetAgentData(FAgentData);
  FAgentStore.SetServices;
  {Setto il registry delle sottoscrizioni}
  {
  var SubSessions := THandleSubscribe.Create(FDDPClient,
   SESSIONS_SUBSCRIPTION, TgrBsonDocument.Create.Add('machine_id', FAgentId));

  var SubCommands := THandleSubscribe.Create(FDDPClient,
   COMMANDS_SUBSCRIPTION, TgrBsonDocument.Create.Add('machine_id', FAgentId));

  LSubscriptionRegistry := GetSubscriptionRegistry;
  LSubscriptionRegistry.RegisterCollection(SubSessions);
  LSubscriptionRegistry.RegisterCollection(SubCommands);
  }
end;

procedure TActionCreatorAgent.OnDisconnect(const ACode: Integer);
begin
  WriteLn(Format('[ActionCreator] Agent disconnect code %d: %s',
    [ACode, FAgentId]));
  FDispatcher.DoDispatch(TFluxAction.Create(ACTION_AGENT_SUBSCRIBE_ERROR,
    TgrBsonDocument.Create.Add('machine_id', FAgentId).Add('code', ACode)));
  StartAutoReconnect;
end;

procedure TActionCreatorAgent.OnError(const AError: string);
begin
  WriteLn('[ActionCreator] Agent error: ' + AError);
  FDispatcher.DoDispatch(TFluxAction.Create(ACTION_AGENT_SUBSCRIBE_ERROR,
    TgrBsonDocument.Create.Add('machine_id', FAgentId).Add('error', AError)));
  StartAutoReconnect;
end;

procedure TActionCreatorAgent.OnException(const AClassName, AMessage: string);
begin
  WriteLn(Format('[ActionCreator] Agent exception %s: %s',
    [AClassName, AMessage]));
  FDispatcher.DoDispatch(TFluxAction.Create(ACTION_AGENT_SUBSCRIBE_ERROR,
    TgrBsonDocument.Create.Add('machine_id', FAgentId).Add('exception',
    AClassName + ': ' + AMessage)));
  StartAutoReconnect;
end;


// Factory function

function GetActionCreatorAgent: IActionCreatorAgent;
begin
  if not Assigned(_ActionCreatorRMCAgent) then
  begin
    _Lock.Enter;
    try
      if not Assigned(_ActionCreatorRMCAgent) then
      begin
        _ActionCreatorRMCAgent := TActionCreatorAgent.Create;
      end;
    finally
      _Lock.Leave;
    end;
  end;
  Result := _ActionCreatorRMCAgent;
end;

procedure Clear;
begin
  _ActionCreatorRMCAgent := nil;
end;

initialization

_Lock := TCriticalSection.Create;

finalization

_Lock.Free;

end.
