program DDPAgent;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.SyncObjs,
  Grijjy.Data.Bson,
  RMCAgent.Config in 'DDPAgent\Core\Config\RMCAgent.Config.pas',
  Shell.Factories in 'DDPAgent\Applications\Shell\Shell.Factories.pas',
  Shell.Exceptions in 'DDPAgent\Applications\Shell\Exceptions\Shell.Exceptions.pas',
  Shell.Runner.Factory in 'DDPAgent\Applications\Shell\Factories\Shell.Runner.Factory.pas',
  Shell.CollectionHandlers in 'DDPAgent\Applications\Shell\Handlers\Shell.CollectionHandlers.pas',
  Shell.MethodHandlers in 'DDPAgent\Applications\Shell\Handlers\Shell.MethodHandlers.pas',
  ShellSession in 'DDPAgent\Applications\Shell\Handlers\ShellSession.pas',
  Shell.Interfaces in 'DDPAgent\Applications\Shell\Interfaces\Shell.Interfaces.pas',
  ShellRunner_PersistentCMD in 'DDPAgent\Applications\Shell\Runners\ShellRunner_PersistentCMD.pas',
  RMC.ShellServiceFactory in 'DDPAgent\Applications\Shell\Services\RMC.ShellServiceFactory.pas',
  RMC.ShellServiceImplementations in 'DDPAgent\Applications\Shell\Services\RMC.ShellServiceImplementations.pas',
  RMC.ShellServiceInterfaces in 'DDPAgent\Applications\Shell\Services\RMC.ShellServiceInterfaces.pas',
  RMC.Store.Agent in 'DDPAgent\Core\Store\RMC.Store.Agent.pas',
  RMC.Store.CollectionHandlers in 'DDPAgent\Core\Store\RMC.Store.CollectionHandlers.pas',
  RMC.Store.CollectionInterface in 'DDPAgent\Core\Store\RMC.Store.CollectionInterface.pas',
  RMC.Store.Events in 'DDPAgent\Core\Store\RMC.Store.Events.pas',
  RMC.Store.MessageDispatcher in 'DDPAgent\Core\Store\RMC.Store.MessageDispatcher.pas',
  RMC.Data in 'DDPAgent\Core\Data\RMC.Data.pas',
  RMC.DataImpl in 'DDPAgent\Core\Data\RMC.DataImpl.pas',
  RMC.DataInterface in 'DDPAgent\Core\Data\RMC.DataInterface.pas',
  AgentServiceI in 'DDPAgent\Core\AgentServiceI.pas',
  Core.Environment in 'DDPAgent\Core\Core.Environment.pas',
  AuthManagerImpl in 'DDPAgent\Applications\Shell\Security\AuthManagerImpl.pas',
  Crypto_Passthrough in 'DDPAgent\Core\Security\Crypto_Passthrough.pas',
  Flux.ActionCreator.Base in 'DDPAgent\Lib\DelphiFlux\Flux.ActionCreator.Base.pas',
  Flux.Actions in 'DDPAgent\Lib\DelphiFlux\Flux.Actions.pas',
  Flux.Dispatcher in 'DDPAgent\Lib\DelphiFlux\Flux.Dispatcher.pas',
  Flux.Store.Base in 'DDPAgent\Lib\DelphiFlux\Flux.Store.Base.pas',
  DDP.ActionCreator.Factory in 'DDPAgent\Lib\DDPClient\DDP.ActionCreator.Factory.pas',
  DDP.ActionCreator in 'DDPAgent\Lib\DDPClient\DDP.ActionCreator.pas',
  DDP.Actions.Consts in 'DDPAgent\Lib\DDPClient\DDP.Actions.Consts.pas',
  DDP.Client in 'DDPAgent\Lib\DDPClient\DDP.Client.pas',
  DDP.Consts in 'DDPAgent\Lib\DDPClient\DDP.Consts.pas',
  DDP.Exception in 'DDPAgent\Lib\DDPClient\DDP.Exception.pas',
  DDP.Factories in 'DDPAgent\Lib\DDPClient\DDP.Factories.pas',
  DDP.Handlers.Base in 'DDPAgent\Lib\DDPClient\DDP.Handlers.Base.pas',
  DDP.Handlers.Method in 'DDPAgent\Lib\DDPClient\DDP.Handlers.Method.pas',
  DDP.Handlers in 'DDPAgent\Lib\DDPClient\DDP.Handlers.pas',
  DDP.Handlers.Subscription in 'DDPAgent\Lib\DDPClient\DDP.Handlers.Subscription.pas',
  RMC.ActionCreator in 'DDPAgent\Core\Actions\RMC.ActionCreator.pas',
  RMC.Actions.Consts in 'DDPAgent\Core\Actions\RMC.Actions.Consts.pas',
  RMC.ActionCreatorDDP in 'DDPAgent\Core\Network\RMC.ActionCreatorDDP.pas',
  RMC.Connection in 'DDPAgent\Core\Network\RMC.Connection.pas',
  RMC.DDP.NetLib.Grijjy in 'DDPAgent\Core\Network\RMC.DDP.NetLib.Grijjy.pas',
  RMC.DDP.NetLib.SGC in 'DDPAgent\Core\Network\RMC.DDP.NetLib.SGC.pas',
  RMC.Store.Connection in 'DDPAgent\Core\Network\RMC.Store.Connection.pas',
  DDP.Interfaces in 'DDPAgent\Lib\DDPClient\DDP.Interfaces.pas',
  DDP.Login in 'DDPAgent\Lib\DDPClient\DDP.Login.pas',
  DDP.NetLib.Factory in 'DDPAgent\Lib\DDPClient\DDP.NetLib.Factory.pas',
  DDP.NetLib.Grijjy in 'DDPAgent\Lib\DDPClient\DDP.NetLib.Grijjy.pas',
  DDP.RequestGenerator in 'DDPAgent\Lib\DDPClient\DDP.RequestGenerator.pas',
  DDP.NetLib.SGC in 'DDPAgent\Lib\DDPClient\DDP.NetLib.SGC.pas';

var
  FAgentId: string;
  Config: TAgentConfig;
  EnvironmentInfo: IEnvironmentInfo;
  ShellRunnerFactory: IShellRunnerFactory;
  Service: IShellSessionService;
  ActionCreator: IActionCreatorAgent;


procedure InitializeConfig;
begin
  WriteLn('[DEBUG] === STARTING InitializeConfig ===');
  try
    WriteLn('[DEBUG] Creating TAgentConfig instance...');
    Config := TAgentConfig.Instance('agent.conf.ini');

    WriteLn('[DEBUG] Loading configuration from file...');
    Config.LoadFromFile;

    WriteLn('[DEBUG] Agent ID: ' + Config.AgentId);
    WriteLn('[DEBUG] Server URL: ' + Config.DppURL);
    WriteLn('[DEBUG] === InitializeConfig COMPLETED ===');
  except
    on E: Exception do
    begin
      WriteLn('[ERROR] InitializeConfig failed: ' + E.ClassName + ': ' + E.Message);
      raise;
    end;
  end;
end;

procedure VerifyFactoryInitialization;
var
  MethodApps, CollectionApps: TArray<string>;
  App: string;
begin
  WriteLn('[DEBUG] === STARTING VerifyFactoryInitialization ===');
  try
  // STEP 0: MANUAL REGISTRATION OF APPLICATION FACTORIES
    WriteLn('[DEBUG] === STEP 0: Registering Application Factories ===');

    // Verifica Method Handler Factory
    WriteLn('[DEBUG] Getting method handler factory...');
    MethodApps := GetMethodHandlerFactory.GetRegisteredApplications;
    WriteLn(Format('[DEBUG] Method Handler Factory: %d applicazioni registrate', [Length(MethodApps)]));
    for App in MethodApps do
      WriteLn(Format('[DEBUG]   - Method App: %s', [App]));

    // Verifica Collection Handler Factory
    WriteLn('[DEBUG] Getting collection handler factory...');
    CollectionApps := GetCollectionHandlerFactory.GetRegisteredApplications;
    WriteLn(Format('[DEBUG] Collection Handler Factory: %d applicazioni registrate', [Length(CollectionApps)]));
    for App in CollectionApps do
      WriteLn(Format('[DEBUG]   - Collection App: %s', [App]));

    if (Length(MethodApps) = 0) or (Length(CollectionApps) = 0) then
    begin
      WriteLn('[WARNING] Alcune factory risultano vuote!');
      WriteLn('[WARNING] Verificare che le unit delle applicazioni siano incluse nella clausola uses');
    end;

    WriteLn('[DEBUG] === VerifyFactoryInitialization COMPLETED ===');
  except
    on E: Exception do
    begin
      WriteLn('[ERROR] VerifyFactoryInitialization failed: ' + E.ClassName + ': ' + E.Message);
      raise;
    end;
  end;
end;

procedure RegisterNetworkFactory;
begin
  WriteLn('[DEBUG] === STARTING RegisterNetworkFactory ===');
  try
    TDDPNetLibFactory.Register(
      function: IDDPNetLib
      begin
        Result := TRMCDDPNetLibGrijjy.Create(Config.DppURL, Config.AgentId);
      end);
    WriteLn('[DEBUG] === RegisterNetworkFactory COMPLETED ===');
  except
    on E: Exception do
    begin
      WriteLn('[ERROR] RegisterNetworkFactory failed: ' + E.ClassName + ': ' + E.Message);
      raise;
    end;
  end;
end;

procedure RegisterDDPActionCreatorFactory;
begin
  WriteLn('[DEBUG] === STARTING RegisterDDPActionCreatorFactory ===');
  try
    TDDPActionCreatorFactory.Register(
      function: IActionCreatorDDP
      begin
        Result := TRMCActionCreatorDDP.Create;
      end);
    WriteLn('[DEBUG] === RegisterDDPActionCreatorFactory COMPLETED ===');
  except
    on E: Exception do
    begin
      WriteLn('[ERROR] RegisterDDPActionCreatorFactory failed: ' + E.ClassName + ': ' + E.Message);
      raise;
    end;
  end;
end;

procedure RegisterSubcription;
begin
  WriteLn('[DEBUG] === STARTING RegisterSubcription ===');
  try
    var SubSessions := THandleSubscribe.Create(
      SESSIONS_SUBSCRIPTION, TgrBsonDocument.Create.Add('machine_id', Config.AgentId));

    var SubCommands := THandleSubscribe.Create(
      COMMANDS_SUBSCRIPTION, TgrBsonDocument.Create.Add('machine_id', Config.AgentId));

    var LSubscriptionRegistry := GetSubscriptionRegistry;
    LSubscriptionRegistry.RegisterCollection(SubSessions);
    LSubscriptionRegistry.RegisterCollection(SubCommands);
    WriteLn('[DEBUG] === RegisterSubcription COMPLETED ===');
  except
    on E: Exception do
    begin
      WriteLn('[ERROR] RegisterSubcription failed: ' + E.ClassName + ': ' + E.Message);
      raise;
    end;
  end;
end;

procedure InitializeServices;
begin
  WriteLn('[DEBUG] === STARTING InitializeServices ===');
  try
    EnvironmentInfo := CreateEnvironmentInfo;
    WriteLn('[DEBUG] === InitializeServices COMPLETED ===');
  except
    on E: Exception do
    begin
      WriteLn('[ERROR] InitializeServices failed: ' + E.ClassName + ': ' + E.Message);
      raise;
    end;
  end;
end;

procedure InitializeActionCreator;
begin
  WriteLn('[DEBUG] === STARTING InitializeActionCreator ===');
  try
    WriteLn('[DEBUG] Getting ActionCreator...');
    ActionCreator := GetActionCreatorAgent;

    WriteLn('[DEBUG] Setting Agent ID...');
    ActionCreator.SetAgentId(Config.AgentId);

    WriteLn('[DEBUG] Getting Agent Store...');
    var AgentStore := GetStoreAgent;
    if not Assigned(AgentStore) then
      raise Exception.Create('Problem with create AgentStore during Build ActionCreator');

    WriteLn('[DEBUG] Creating ShellRunnerFactory...');
    ShellRunnerFactory := TShellRunnerFactory.Create(EnvironmentInfo);

    WriteLn('[DEBUG] Creating Shell Service Factory...');
    var FTShellServiceFactory := TShellServiceFactory.Create;

    WriteLn('[DEBUG] Registering Shell Session Service...');
    FTShellServiceFactory.RegisterShellSessionService(
      Config.Instance.AgentId,
      ShellRunnerFactory,
      TCommandValidator.Create,
      Config.Instance.SessionLimit,
      'auth_rules.txt'
    );
    RegisterShellFactories(FTShellServiceFactory);
    WriteLn('[DEBUG] === InitializeActionCreator COMPLETED ===');
  except
    on E: Exception do
    begin
      WriteLn('[ERROR] InitializeActionCreator failed: ' + E.ClassName + ': ' + E.Message);
      raise;
    end;
  end;
end;

procedure ConnectAndLogin;
begin
  WriteLn('[DEBUG] === STARTING ConnectAndLogin ===');
  try
    if Config.Token <> '' then
    begin
      WriteLn('[DEBUG] Using token authentication...');
      ActionCreator.Login(Config.Token);
    end
    else
    begin
      WriteLn('[ERROR] No authentication credentials configured');
      raise Exception.Create('No authentication credentials configured');
    end;

    WriteLn('[DEBUG] Final connection status: ' + ActionCreator.GetConnectionStatus);
    WriteLn('[DEBUG] === ConnectAndLogin COMPLETED ===');
  except
    on E: Exception do
    begin
      WriteLn('[ERROR] ConnectAndLogin failed: ' + E.ClassName + ': ' + E.Message);
      raise;
    end;
  end;
end;

procedure Cleanup;
begin
  WriteLn('[DEBUG] === STARTING Cleanup ===');
  try
    if Assigned(ActionCreator) then
    begin
      WriteLn('[DEBUG] Logging out ActionCreator...');
      ActionCreator.Logout;
      ActionCreator := nil;
    end;
    if Assigned(Config) then
    begin
      WriteLn('[DEBUG] Freeing Config...');
      Config.Free;
      Config := nil;
    end;
    WriteLn('[DEBUG] === Cleanup COMPLETED ===');
  except
    on E: Exception do
      WriteLn('[ERROR] Error during cleanup: ' + E.Message);
  end;
end;


procedure ProcessResults;
var
  Result: TMethodResult;
  FAGD: IAgentData;
begin
  FAGD :=  ActionCreator.GetRMCAgentData;
  while FAGD.ResultQueue.PopItem(Result) = wrSignaled do
  begin
    if Result.Success then
      WriteLn(Format('[Result] %s: %s', [Result.MethodName, Result.Result]))
    else
      WriteLn(Format('[Error] %s: %s', [Result.MethodName, Result.Error]));
  end;
end;

procedure RunMainLoop;
begin
  WriteLn('Starting main loop with message processing...');
  var
  intx := 1;
  // while not ShouldTerminate do
  for var I := 1 to 100000 do // simula un ciclo principale
  begin
    // *** CHIAVE: Processa messaggi dai thread secondari ***
    ProcessResults;
    Sleep(10);
  end;
end;

 begin
  WriteLn('[DEBUG] ========================================');
  WriteLn('[DEBUG] === RMC DDP Agent v1.0 STARTING ===');
  WriteLn('[DEBUG] ========================================');
  try

  InitializeConfig;

  // Step 3: Infrastruttura di rete
  RegisterNetworkFactory;
  RegisterDDPActionCreatorFactory;
  // Step 4: Sottoscrizioni
  RegisterSubcription;

  // Step 5: Servizi
  InitializeServices;

  // Step 1: Verifica factory
  VerifyFactoryInitialization;
  InitializeActionCreator;
  // Step 7: Connessione

  ConnectAndLogin;

  RunMainLoop;

  except
    on E: Exception do
    begin
      WriteLn('[ERROR] ========================================');
      WriteLn('[ERROR] CRITICAL ERROR IN MAIN PROGRAM:');
      WriteLn('[ERROR] Exception Class: ' + E.ClassName);
      WriteLn('[ERROR] Exception Message: ' + E.Message);
      WriteLn('[ERROR] ========================================');

      WriteLn('[ERROR] Press Enter to exit...');
      ReadLn;
    end;
  end;

  WriteLn('[DEBUG] Calling cleanup...');
  Cleanup;

  WriteLn('[DEBUG] Final cleanup - Press Enter to exit...');
  ReadLn;
end.

