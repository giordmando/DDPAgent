unit RMC.Store.Agent;

interface

uses
        DDP.Actions.Consts,
        RMC.Actions.Consts,
        RMC.Store.Events,
        Flux.Actions,
        Flux.Store.Base,
        Grijjy.Data.Bson,
        Grijjy.System.Messaging,
        System.SysUtils,
        System.JSON,
        RMC.Store.CollectionInterface,
        RMC.Store.MessageDispatcher,
        RMC.Data,
        AgentServiceI,
        RMCAgent.Config;

type
        IStoreAgent = interface
          // Core setup
          procedure SetAgentData(const AAgentData: IAgentData);
          // Actions (unchanged)
          procedure OnAction(const ASender: TObject; const AAction: TgrMessage);
          procedure SetServices;

        end;

        TStoreAgent = class(TStoreBase, IStoreAgent)
        private
                FMessageDispatcher: IMessageDispatcher;
                FHandlerFactory: ICollectionHandlerFactory;
                FAgentHandlers: TArray<ICollectionHandler>;
                FAgentId: string;
                FAgentData: IAgentData;
                //FShellSessionService: IApplicationService;


                procedure InitializeHandlers;
                procedure HandleGeneralActions(const AActionType: string; const ADoc: TgrBsonDocument);
        protected
                procedure EmitStoreChange; override;
                procedure SetServices;

                { IStoreAgent implementation }
                procedure SetAgentData(const AAgentData: IAgentData);

        public
                constructor Create; overload;
                destructor Destroy; override;
                procedure OnAction(const ASender: TObject;
                  const AAction: TgrMessage); override;
        end;

function GetStoreAgent: IStoreAgent;

implementation

uses
        System.SyncObjs,
        RMC.Store.CollectionHandlers;

var
        _Lock: TCriticalSection;
        _StoreAgent: IStoreAgent;

        { TStoreAgent }

constructor TStoreAgent.Create;
begin
  inherited Create;
  FMessageDispatcher := TMessageDispatcher.Create;
  FHandlerFactory   := GetCollectionHandlerFactory;
  FAgentId:=TAgentConfig.Instance.AgentId;
end;

destructor TStoreAgent.Destroy;
var
  H: ICollectionHandler;
begin
  // deregistrare handler se necessario
  for H in FAgentHandlers do
    FMessageDispatcher.UnregisterHandler(H.GetCollectionName);
  FAgentHandlers := nil;
  FMessageDispatcher := nil;
  inherited;
end;

procedure TStoreAgent.InitializeHandlers;
var
  H: ICollectionHandler;
begin
  if (FAgentId = '') or not Assigned(FAgentData) then //or not Assigned(FShellSessionService) then
    Exit;

  // crea tutti gli handler in un colpo solo
  FAgentHandlers := FHandlerFactory.CreateHandlers(
    FAgentId, FAgentData, EmitStoreChange);

  // registrali automaticamente
  for H in FAgentHandlers do
    FMessageDispatcher.RegisterHandler(H);
end;


procedure TStoreAgent.SetServices;
begin
  WriteLn('[StoreAgent] Setting up services...');
  //FShellSessionService := AShellSessionService;
  InitializeHandlers;
  WriteLn('[StoreAgent] Services configured successfully');
end;


procedure TStoreAgent.SetAgentData(const AAgentData: IAgentData);
begin
  FAgentData := AAgentData;
end;

procedure TStoreAgent.EmitStoreChange;
begin
  FDispatcher.DoDispatch(TStoreRMCDataChangedMessage.Create);
end;

procedure TStoreAgent.OnAction(const ASender: TObject; const AAction: TgrMessage);
var
  LAction: TFluxAction absolute AAction;
  LActionType: string;
  LDoc: TgrBsonDocument;
begin
  WriteLn('[DEBUG TStoreAgent] OnAction chiamato');
  Assert(AAction is TFluxAction);

  LActionType := LAction.&Type;
  WriteLn('[DEBUG TStoreAgent] Action type: ' + LActionType);

  if not LAction.Data.IsNil then
    LDoc := LAction.Data
  else
    LDoc := Default(TgrBsonDocument);

  // Handle general actions
  HandleGeneralActions(LActionType, LDoc);

  // Dispatch DDP document actions to appropriate handlers
  if (LActionType = ACTION_DDP_DOCUMENT_ADDED) then
  begin
    if not (LDoc = Default(TgrBsonDocument)) and Assigned(FMessageDispatcher) then
      FMessageDispatcher.DispatchMessage(LActionType, LDoc);
  end;

   if (LActionType = ACTION_DDP_DOCUMENT_CHANGED) then
  begin
    if not (LDoc = Default(TgrBsonDocument)) and Assigned(FMessageDispatcher) then
      FMessageDispatcher.DispatchMessage(LActionType, LDoc);
  end;

   if (LActionType = ACTION_DDP_DOCUMENT_REMOVED) then
  begin
    if not (LDoc = Default(TgrBsonDocument)) and Assigned(FMessageDispatcher) then
      FMessageDispatcher.DispatchMessage(LActionType, LDoc);
  end;
end;

procedure TStoreAgent.HandleGeneralActions(const AActionType: string; const ADoc: TgrBsonDocument);
begin
  if AActionType = TEST_PING then
  begin
    if Assigned(FAgentData) then
      FAgentData.OnMethod(AActionType, ADoc);
  end
  else if AActionType = ACTION_DDP_LOGGING_OUT then
  begin
    WriteLn('[StoreAgent] *** TODO Clear All Sessions and Command ***');
    FMessageDispatcher.DispatchMessage(AActionType, ADoc);
  end
  else if AActionType = ACTION_DDP_CONNECTING then
  begin
    WriteLn('[DEBUG TStoreAgent] ACTION_DDP_CONNECTING: ' + AActionType);
  end
  else if (AActionType = ACTION_DDP_CONNECTED) or (AActionType = ACTION_DDP_DISCONNECTED) then
  begin
    EmitStoreChange;
  end;
end;

// Factory function
function GetStoreAgent: IStoreAgent;
begin
  if not Assigned(_StoreAgent) then
  begin
    _Lock.Enter;
    try
      _StoreAgent := TStoreAgent.Create;
      WriteLn('[DEBUG] StoreAgent created and registered');

    finally
      _Lock.Leave;
    end;
  end;
  Result := _StoreAgent;
end;

initialization

_Lock := TCriticalSection.Create;

finalization

_Lock.Free;

end.
