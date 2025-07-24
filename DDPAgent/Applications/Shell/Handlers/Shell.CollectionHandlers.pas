unit Shell.CollectionHandlers;

interface

uses
  RMC.Store.CollectionInterface, AgentServiceI,
  System.SysUtils, Grijjy.Data.Bson, System.Threading,
  System.Generics.Collections, Shell.Interfaces;

type
   TGenProc = reference to procedure(const Doc: TgrBsonDocument);
  // Session collection handler
  TSessionHandler = class(TInterfacedObject, ICollectionHandler)
  private
    FAgentId: string;
    FAgentData: IAgentData;
    FShellService: IShellSessionService;
    FOnDataChanged: TProc;
    FHandlers: TDictionary<string, TGenProc>;

    procedure RegisterHandlers;
    procedure HandleSessionAdded(const ADoc: TgrBsonDocument);
    procedure HandleSessionChanged(const ADoc: TgrBsonDocument);
    procedure HandleSessionRemoved(const ADoc: TgrBsonDocument);
  public
    function GetCollectionName: string;
    function CanHandle(const AActionType: string): Boolean;
    procedure HandleAction(const AActionType: string; const ADoc: TgrBsonDocument);
  public
    constructor Create(const AgentId: string; const AgentData: IAgentData;
    const ShellSessionService:IShellSessionService; const OnDataChanged: TProc);
  end;

  // Command collection handler
  TCommandHandler = class(TInterfacedObject, ICollectionHandler)
  private
    FAgentId: string;
    FAgentData: IAgentData;
    FShellService: IShellSessionService;
    FOnDataChanged: TProc;
    FHandlers: TDictionary<string, TGenProc>;

    procedure RegisterHandlers;
    procedure HandleCommandAdded(const ADoc: TgrBsonDocument);
    procedure HandleCommandChanged(const ADoc: TgrBsonDocument);
    procedure HandleCommandRemoved(const ADoc: TgrBsonDocument);
  protected
    function GetCollectionName: string;
    function CanHandle(const AActionType: string): Boolean;
    procedure HandleAction(const AActionType: string; const ADoc: TgrBsonDocument);
  public
    constructor Create(const AgentId: string; const AgentData: IAgentData;
      const ShellSessionService:IShellSessionService; const OnDataChanged: TProc);
  end;

implementation

uses
  DDP.Actions.Consts, RMC.Actions.Consts;

{ TSessionHandler }

constructor TSessionHandler.Create(const AgentId: string; const AgentData: IAgentData;
   const ShellSessionService:IShellSessionService; const OnDataChanged: TProc);
begin
  inherited Create;
  FAgentId := AgentId;
  FAgentData := AgentData;
  FShellService := ShellSessionService; // TODO QUI va recuperato il servizio Singleton?
  FOnDataChanged := OnDataChanged;
  FHandlers := TDictionary<string, TGenProc>.Create;
  RegisterHandlers;
end;

procedure TSessionHandler.RegisterHandlers;
begin
  // Mappa le costanti ACTION_DDP_... alle rispettive procedure
  FHandlers.Add(ACTION_DDP_DOCUMENT_ADDED, HandleSessionAdded);
  FHandlers.Add(ACTION_DDP_DOCUMENT_CHANGED, HandleSessionChanged);
  FHandlers.Add(ACTION_DDP_DOCUMENT_REMOVED, HandleSessionRemoved);
  FHandlers.Add(ACTION_DDP_LOGGING_OUT, HandleSessionRemoved);

  // Per aggiungere nuove azioni basta qui: FHandlers.Add('MY_ACTION', MyHandler);
end;

function TSessionHandler.GetCollectionName: string;
begin
  Result := 'sessions'; // From SESSIONS_SUBSCRIPTION = 'agent.sessions'
end;

function TSessionHandler.CanHandle(const AActionType: string): Boolean;
begin
  Result := FHandlers.ContainsKey(AActionType);
end;

procedure TSessionHandler.HandleAction(const AActionType: string; const ADoc: TgrBsonDocument);
  var
  Handler: TGenProc;
begin
  // Se abbiamo un handler registrato, lo chiamiamo
  if FHandlers.TryGetValue(AActionType, Handler) then
    Handler(ADoc)
  else
    // eventualmente log di azione non gestita
    Writeln(Format('[SessionHandler] Unhandled action: %s', [AActionType]));
end;

procedure TSessionHandler.HandleSessionAdded(const ADoc: TgrBsonDocument);
var
  SessionId, UserId, ShellType, AgentId: string;
begin
  WriteLn('[SessionHandler] *** NEW SESSION RECEIVED ***');

  if ADoc.Contains('fields') then
  begin
    var Fields := ADoc['fields'].AsBsonDocument;

    if Fields.Contains('machine_id') then
      AgentId := Fields['machine_id'].AsString;

    if Fields.Contains('session_id') then
      SessionId := Fields['session_id'].AsString;

    if (Fields.Contains('status')) and (Fields['status'].ToString <> 'requested') then
    begin
      WriteLn(Format('[SessionHandler] session already open - Agent: %s Session_id: %s)',
        [AgentId, SessionId]));
      Exit;
    end;

    if AgentId <> FAgentId then
    begin
      WriteLn(Format('[SessionHandler] Session ignored - wrong machine_id: %s (expected: %s)',
        [AgentId, FAgentId]));
      Exit;
    end;

    if Fields.Contains('client_id') then
      UserId := Fields['client_id'].AsString;

    if Fields.Contains('shell_type') then
      ShellType := Fields['shell_type'].AsString;

    WriteLn('[SessionHandler] Session for this agent:');
    WriteLn(Format('[SessionHandler]   Session ID: %s', [SessionId]));
    WriteLn(Format('[SessionHandler]   User ID: %s', [UserId]));
    WriteLn(Format('[SessionHandler]   Shell Type: %s', [ShellType]));

    if Assigned(FShellService) then
    begin
      FShellService.CreateSession(ShellType, SessionId);
      if Assigned(FAgentData) then
      FAgentData.OnMethod(SESSION_STATUS, TgrBsonDocument.Create.Add('machine_id', FAgentId)
      .Add('session_id', SessionId)
      .Add('status', 'opened'));
    end;

    if Assigned(FOnDataChanged) then
      FOnDataChanged();
  end;
end;

procedure TSessionHandler.HandleSessionChanged(const ADoc: TgrBsonDocument);
var
  SessionId, ShellType, AgentId: string;
  Fields: TgrBsonDocument; // Assumi che sia già popolato
  Id: string;
  Value: TgrBsonValue; // Questo è il tipo del valore recuperato
begin
  WriteLn('[SessionHandler] *** SESSION CHANGED ***');
  if ADoc.Contains('id') then
    Id :=  ADoc['id'];

  if ADoc.Contains('fields') then
  begin
    Fields := ADoc['fields'].AsBsonDocument;

    if Fields.Contains('machine_id') then
      AgentId := Fields['machine_id'].AsString;

    if Fields.Contains('session_id') then
      SessionId := Fields['session_id'].AsString;

    if (Fields.Contains('status')) and (Fields['status'].ToString = 'closed') then
    begin
      WriteLn('[SessionHandler] Session for this agent:');
      WriteLn(Format('[SessionHandler]   Session ID: %s', [Id]));

      if Assigned(FShellService) then
        FShellService.CloseSession(SessionId);
        FAgentData.OnMethod(SESSION_CLOSE,
        TgrBsonDocument.Create.Add('machine_id', FAgentId)
        .Add('session_id', SessionId));
      if Assigned(FOnDataChanged) then
        FOnDataChanged();
    end
    else if (Fields.Contains('status')) and (Fields['status'].ToString = 'opened') then
    begin
      WriteLn('[SessionHandler] Opened @@@@@@@@@@@@@@@@@@@@@ '+ADoc.ToJson);
    end
  end;
end;

procedure TSessionHandler.HandleSessionRemoved(const ADoc: TgrBsonDocument);
begin
  WriteLn('[SessionHandler] Session removed');
  if Assigned(FOnDataChanged) then
    FOnDataChanged();
end;

{ TCommandHandler }

constructor TCommandHandler.Create(const AgentId: string; const AgentData: IAgentData;
   const ShellSessionService:IShellSessionService; const OnDataChanged: TProc);
begin
  inherited Create;
  FAgentId := AgentId;
  FAgentData := AgentData;
  FShellService := ShellSessionService;
  FOnDataChanged := OnDataChanged;
  FHandlers := TDictionary<string, TGenProc>.Create;
  RegisterHandlers;
end;

function TCommandHandler.GetCollectionName: string;
begin
  Result := 'commands'; // From COMMANDS_SUBSCRIPTION = 'agent.commands'
end;

function TCommandHandler.CanHandle(const AActionType: string): Boolean;
begin
  Result := FHandlers.ContainsKey(AActionType);
end;

procedure TCommandHandler.RegisterHandlers;
begin
  // Mappa le costanti ACTION_DDP_... alle rispettive procedure
  FHandlers.Add(ACTION_DDP_DOCUMENT_ADDED, HandleCommandAdded);
  FHandlers.Add(ACTION_DDP_DOCUMENT_CHANGED, HandleCommandChanged);
  FHandlers.Add(ACTION_DDP_DOCUMENT_REMOVED, HandleCommandRemoved);

  // Per aggiungere nuove azioni basta qui: FHandlers.Add('MY_ACTION', MyHandler);
end;

procedure TCommandHandler.HandleAction(const AActionType: string; const ADoc: TgrBsonDocument);
var
  Handler: TGenProc;
begin
  // Se abbiamo un handler registrato, lo chiamiamo
  if FHandlers.TryGetValue(AActionType, Handler) then
    Handler(ADoc)
  else
    // eventualmente log di azione non gestita
    Writeln(Format('[SessionHandler] Unhandled action: %s', [AActionType]));
end;

procedure TCommandHandler.HandleCommandAdded(const ADoc: TgrBsonDocument);
var
  CommandId, SessionId, CommandLine: string;
  AgentId: string;
  Priority, Timeout: Integer;
begin
  WriteLn('[CommandHandler] *** NEW COMMAND RECEIVED ***');

  if ADoc.Contains('id') then
    CommandId := ADoc['id'].AsString;

  if ADoc.Contains('fields') then
  begin
    var Fields := ADoc['fields'].AsBsonDocument;

    if Fields.Contains('machine_id') then
      AgentId := Fields['machine_id'].AsString;

    if AgentId <> FAgentId then
    begin
      WriteLn(Format('[CommandHandler] Command ignored - wrong machine_id: %s (expected: %s)',
        [AgentId, FAgentId]));
      Exit;
    end;

    if Fields.Contains('session_id') then
      SessionId := Fields['session_id'].AsString;

    if Fields.Contains('commandLine') then
      CommandLine := Fields['commandLine'].AsString;


    WriteLn('[CommandHandler] Command for this agent:');
    WriteLn(Format('[CommandHandler]   Command ID: %s', [CommandId]));
    WriteLn(Format('[CommandHandler]   Session ID: %s', [SessionId]));
    WriteLn(Format('[CommandHandler]   Command: %s', [CommandLine]));

    if Assigned(FShellService) then
    begin
      WriteLn('[CommandHandler] Executing command...');
      FShellService.ExecuteCommand(SessionId, CommandId, CommandLine);
      FAgentData.OnMethod(COMMAND_EXECUTION, TgrBsonDocument.Create.Add('command_id', CommandId));
    end;

    if Assigned(FOnDataChanged) then
      FOnDataChanged();
  end;
end;

procedure TCommandHandler.HandleCommandChanged(const ADoc: TgrBsonDocument);
begin
  WriteLn('[CommandHandler] Command changed');
  if Assigned(FOnDataChanged) then
    FOnDataChanged();
end;

procedure TCommandHandler.HandleCommandRemoved(const ADoc: TgrBsonDocument);
var
  CommandId, SessionId, CommandLine: string;
  AgentId: string;
begin
  WriteLn('[CommandHandler] Command removed');

   WriteLn('[CommandHandler] *** REMOVE COMMAND RECEIVED ***');

  if ADoc.Contains('id') then
    CommandId := ADoc['id'].AsString;

  if ADoc.Contains('fields') then
  begin
    var Fields := ADoc['fields'].AsBsonDocument;

    if Fields.Contains('machine_id') then
      AgentId := Fields['machine_id'].AsString;

    if AgentId <> FAgentId then
    begin
      WriteLn(Format('[CommandHandler] Command ignored - wrong machine_id: %s (expected: %s)',
        [AgentId, FAgentId]));
      Exit;
    end;

    if Fields.Contains('session_id') then
      SessionId := Fields['session_id'].AsString;

    if Fields.Contains('commandLine') then
      CommandLine := Fields['commandLine'].AsString;
  end;

  if Assigned(FOnDataChanged) then
    FOnDataChanged();
end;


end.
