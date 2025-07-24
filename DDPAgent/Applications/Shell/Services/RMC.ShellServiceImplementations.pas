unit RMC.ShellServiceImplementations;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.SyncObjs,
  System.DateUtils,
  System.JSON,
  System.Masks,
  AgentServiceI,
  RMC.Data,
  RMC.Actions.Consts,
  Grijjy.Data.Bson,
  Shell.Interfaces;

type

  TRunningCommandInfo = record
    CommandId: string;
    SessionId: string;
    StartTime: TDateTime;
    CommandText: string;
  end;

  // Implementazione validator comandi
  TCommandValidator = class(TInterfacedObject, ICommandValidator)
  private
    FWhitelist: TStrings;
    FBlacklist: TStrings;
    FLock: TCriticalSection;
    function CheckList(const ACommand: string; const AList: TStrings): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function ValidateCommand(const ACommand: string): TCommandValidationResult;
    procedure LoadRules(const ASource: string);
    procedure AddToWhitelist(const ACommandPattern: string);
    procedure AddToBlacklist(const ACommandPattern: string);
    procedure Clear;
  end;

  // Implementazione limiter sessioni
  TSessionLimiter = class(TInterfacedObject, ISessionLimiter)
  private
    FMaxSessions: Integer;
    FSessionRepository: ISessionRepository;
    FLock: TCriticalSection;
  public
    constructor Create(const ASessionRepository: ISessionRepository; AMaxSessions: Integer = 10);
    destructor Destroy; override;
    function CanCreateSession: Boolean;
    function GetMaxSessions: Integer;
    function GetActiveSessionCount: Integer;
    procedure SetMaxSessions(const AValue: Integer);
  end;

  // Implementazione output handler
  TOutputHandler = class(TInterfacedObject, IOutputHandler)
  private
    FAgentId: string;
    FAgentData: IAgentData;
    FLock: TCriticalSection;
  public
    constructor Create(const AAgentId: string; const AAgentData: IAgentData);
    destructor Destroy; override;
    procedure HandleOutput(const ASessionId: string; const CommandId: string; const ALine: string);
    procedure HandleError(const ASessionId: string; const CommandId: string; const ALine: string);
    procedure HandleCommandComplete(const ACommandId: string; const AExitCode: Integer);
    procedure HandleValidationError(const ACommandId, ASessionId: string;
      const ACommand, AErrorMessage: string);
    procedure HandleExecutionError(const ACommandId, ASessionId: string;
      const ACommand, AErrorMessage: string);
  end;

  // Implementazione executor shell
  TShellExecutor = class(TInterfacedObject, IShellExecutor)
  private
    FSessionRepository: ISessionRepository;
    FShellRunnerFactory: IShellRunnerFactory;
    FRunningCommands: TDictionary<string, TRunningCommandInfo>;
    FRunningBySession: TDictionary<string, string>;
    FOutputHandler: IOutputHandler;
    FLock: TCriticalSection;
    procedure CleanupCommand(const ACommandId: string);
  public
    constructor Create(const ASessionRepository: ISessionRepository;
      const AShellRunnerFactory: IShellRunnerFactory);
    destructor Destroy; override;
    procedure ExecuteCommand(const ASessionId: string; const CommandId : string ; const ACommand: string);
    function IsCommandRunning(const ACommandId: string): Boolean;
    procedure CancelCommand(const ASessionId: string);
    procedure SetOutputHandler(const AHandler: IOutputHandler);

    function IsSessionBusy(const ASessionId: string): Boolean;  // NUOVO
    function GetRunningCommandForSession(const ASessionId: string): string;  // NUOVO
  end;

  // Implementazione repository sessioni
  TSessionRepository = class(TInterfacedObject, ISessionRepository)
  private
    FSessions: TDictionary<string, TSessionInfo>;
    FShellSessions: TDictionary<string, IShellSession>;
    FShellFactory: IShellRunnerFactory;
    FLock: TCriticalSection;
    function GenerateSessionId: string;
  public
    constructor Create(const AShellFactory: IShellRunnerFactory);
    destructor Destroy; override;
    function CreateSession(const AShellType: string; const ASessionId: string = ''): TSessionInfo;
    function GetSession(const ASessionId: string): TSessionInfo;
    function GetAllSessions: TArray<TSessionInfo>;
    function SessionExists(const ASessionId: string): Boolean;
    procedure UpdateSessionActivity(const ASessionId: string);
    procedure CloseSession(const ASessionId: string);
    procedure CloseAllSessions;
    function GetActiveSessionCount: Integer;
    procedure CleanupInactiveSessions(const ATimeoutMinutes: Integer);
    function GetShellSession(const ASessionId: string): IShellSession;
  end;

  // Servizio principale
  TShellSessionService = class(TInterfacedObject, IShellSessionService)
  private
    FValidator: ICommandValidator;
    FLimiter: ISessionLimiter;
    FExecutor: IShellExecutor;
    FRepository: ISessionRepository;
    FOutputHandler: IOutputHandler;
    FLock: TCriticalSection;
  public
    constructor Create(const AValidator: ICommandValidator;
      const ALimiter: ISessionLimiter; const AExecutor: IShellExecutor;
      const ARepository: ISessionRepository; const AOutputHandler: IOutputHandler);
    destructor Destroy; override;
    function CreateSession(const AShellType: string; const ASessionId: string = ''): TSessionInfo;
    function ExecuteCommand(const ASessionId: string;
      const CommandId: string; const ACommand: string): TCommandExecutionResult;
    function GetSession(const ASessionId: string): TSessionInfo;
    function GetAllSessions: TArray<TSessionInfo>;
    procedure CloseSession(const ASessionId: string);
    procedure CloseAllSessions;
    function GetServiceStats: TJSONObject;
    procedure HandleValidationFailure(const ASessionId, ACommandId, ACommand, AErrorMessage: string; const AStartTime: TDateTime);
    procedure HandleExecutionFailure(const ASessionId, ACommandId, ACommand, AErrorMessage: string; const AStartTime: TDateTime);

  end;

implementation

uses
  ShellSession;

// Aggiungi costanti per gli exit codes
const
  EXIT_CODE_SUCCESS = 0;
  EXIT_CODE_VALIDATION_ERROR = 403;  // Forbidden/Unauthorized
  EXIT_CODE_EXECUTION_ERROR = 500;   // Internal Server Error
  EXIT_CODE_SESSION_ERROR = 404;     // Session Not Found
  EXIT_CODE_TIMEOUT = 408;           // Request Timeout
  EXIT_CODE_CANCELLED = 499;         // Client Closed Request

{ TCommandValidator }

constructor TCommandValidator.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FWhitelist := TStringList.Create;
  FBlacklist := TStringList.Create;
end;

destructor TCommandValidator.Destroy;
begin
  FWhitelist.Free;
  FBlacklist.Free;
  FLock.Free;
  inherited;
end;

function TCommandValidator.CheckList(const ACommand: string; const AList: TStrings): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to AList.Count - 1 do
  begin
    if MatchesMask(ACommand, AList[i]) then
    begin
      Result := True;
      Break;
    end;
  end;
end;

function TCommandValidator.ValidateCommand(const ACommand: string): TCommandValidationResult;
begin
  FLock.Enter;
  try
    WriteLn(Format('[CommandValidator] Validating command: "%s"', [ACommand]));

    // Verifica blacklist prima
    if CheckList(ACommand, FBlacklist) then
    begin
      WriteLn(Format('[CommandValidator] Command BLOCKED by blacklist: "%s"', [ACommand]));
      Result := TCommandValidationResult.Failure('Comando bloccato dalla blacklist');
      Exit; // Opzionale, ma più chiaro
    end;

    // Se whitelist vuota, tutto è permesso (eccetto blacklist)
    if FWhitelist.Count = 0 then
    begin
      WriteLn(Format('[CommandValidator] Command ALLOWED (empty whitelist): "%s"', [ACommand]));
      Result := TCommandValidationResult.Success;
      Exit; // Opzionale
    end;

    // Verifica whitelist
    if CheckList(ACommand, FWhitelist) then
    begin
      WriteLn(Format('[CommandValidator] Command ALLOWED by whitelist: "%s"', [ACommand]));
      Result := TCommandValidationResult.Success;
    end
    else
    begin
      WriteLn(Format('[CommandValidator] Command DENIED (not in whitelist): "%s"', [ACommand]));
      Result := TCommandValidationResult.Failure('Comando non autorizzato');
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TCommandValidator.LoadRules(const ASource: string);
var
  Rules: TStringList;
  Line: string;
begin
  if not FileExists(ASource) then
    Exit;

  Rules := TStringList.Create;
  try
    Rules.LoadFromFile(ASource);
    FLock.Enter;
    try
      FWhitelist.Clear;
      FBlacklist.Clear;
      for Line in Rules do
      begin
        if Line.StartsWith('+') then
          FWhitelist.Add(Line.Substring(1).Trim)
        else if Line.StartsWith('-') then
          FBlacklist.Add(Line.Substring(1).Trim);
      end;
    finally
      FLock.Leave;
    end;
  finally
    Rules.Free;
  end;
end;

procedure TCommandValidator.AddToWhitelist(const ACommandPattern: string);
begin
  FLock.Enter;
  try
    FWhitelist.Add(ACommandPattern);
  finally
    FLock.Leave;
  end;
end;

procedure TCommandValidator.AddToBlacklist(const ACommandPattern: string);
begin
  FLock.Enter;
  try
    FBlacklist.Add(ACommandPattern);
  finally
    FLock.Leave;
  end;
end;

procedure TCommandValidator.Clear;
begin
  FLock.Enter;
  try
    FWhitelist.Clear;
    FBlacklist.Clear;
  finally
    FLock.Leave;
  end;
end;

{ TSessionLimiter }

constructor TSessionLimiter.Create(const ASessionRepository: ISessionRepository; AMaxSessions: Integer);
begin
  inherited Create;
  FSessionRepository := ASessionRepository;
  FMaxSessions := AMaxSessions;
  FLock := TCriticalSection.Create;
end;

destructor TSessionLimiter.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TSessionLimiter.CanCreateSession: Boolean;
begin
  FLock.Enter;
  try
    Result := FSessionRepository.GetActiveSessionCount < FMaxSessions;
  finally
    FLock.Leave;
  end;
end;

function TSessionLimiter.GetMaxSessions: Integer;
begin
  FLock.Enter;
  try
    Result := FMaxSessions;
  finally
    FLock.Leave;
  end;
end;

function TSessionLimiter.GetActiveSessionCount: Integer;
begin
  Result := FSessionRepository.GetActiveSessionCount;
end;

procedure TSessionLimiter.SetMaxSessions(const AValue: Integer);
begin
  FLock.Enter;
  try
    FMaxSessions := AValue;
  finally
    FLock.Leave;
  end;
end;

{ TOutputHandler }

constructor TOutputHandler.Create(const AAgentId: string; const AAgentData: IAgentData);
begin
  inherited Create;
  FAgentId := AAgentId;
  FAgentData := AAgentData;
  FLock := TCriticalSection.Create;
end;

destructor TOutputHandler.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TOutputHandler.HandleOutput(const ASessionId: string; const CommandId: string; const ALine: string);
begin
  FLock.Enter;
  try
    if Assigned(FAgentData) then
      //FAgentData.SendOutput(FAgentId, ASessionId, 'stdout', ALine);
      FAgentData.OnMethod(COMMAND_OUTPUT, TgrBsonDocument.Create
            .Add('machine_id', FAgentId)
            .Add('session_id', ASessionId)
            .Add('command_id', CommandId)
            .Add('stream', 'stdout')
            .Add('data', ALine)
            .Add('timestamp', DateToISO8601(Now, True)));
  finally
    FLock.Leave;
  end;
end;

procedure TOutputHandler.HandleError(const ASessionId: string; const CommandId: string; const ALine: string);
begin
  FLock.Enter;
  try
    if Assigned(FAgentData) then
      //FAgentData.SendOutput(FAgentId, ASessionId, 'stderr', ALine);
      FAgentData.OnMethod(COMMAND_OUTPUT, TgrBsonDocument.Create
            .Add('machine_id', FAgentId)
            .Add('session_id', ASessionId)
            .Add('command_id', CommandId)
            .Add('stream', 'stderr')
            .Add('data', ALine)
            .Add('timestamp', DateToISO8601(Now, True)));
  finally
    FLock.Leave;
  end;
end;

procedure TOutputHandler.HandleCommandComplete(const ACommandId: string; const AExitCode: Integer);
var
  Status: string;
  ErrorType: string;
begin
  FLock.Enter;
  try
    if Assigned(FAgentData) then
    begin
      // Determina lo stato basato sull'exit code
      case AExitCode of
        EXIT_CODE_SUCCESS:
        begin
          Status := 'completed';
          ErrorType := '';
          WriteLn(Format('[OutputHandler] Command %s completed successfully', [ACommandId]));
        end;
        EXIT_CODE_VALIDATION_ERROR:
        begin
          Status := 'failed';
          ErrorType := 'validation_error';
          WriteLn(Format('[OutputHandler] Command %s failed validation', [ACommandId]));
        end;
        EXIT_CODE_EXECUTION_ERROR:
        begin
          Status := 'failed';
          ErrorType := 'execution_error';
          WriteLn(Format('[OutputHandler] Command %s failed execution', [ACommandId]));
        end;
        EXIT_CODE_SESSION_ERROR:
        begin
          Status := 'failed';
          ErrorType := 'session_error';
          WriteLn(Format('[OutputHandler] Command %s failed - session error', [ACommandId]));
        end;
        EXIT_CODE_TIMEOUT:
        begin
          Status := 'timeout';
          ErrorType := 'timeout';
          WriteLn(Format('[OutputHandler] Command %s timed out', [ACommandId]));
        end;
        EXIT_CODE_CANCELLED:
        begin
          Status := 'cancelled';
          ErrorType := 'cancelled';
          WriteLn(Format('[OutputHandler] Command %s was cancelled', [ACommandId]));
        end;
      else
        begin
          Status := 'failed';
          ErrorType := 'unknown_error';
          WriteLn(Format('[OutputHandler] Command %s completed with unknown exit code %d',
            [ACommandId, AExitCode]));
        end;
      end;

      // *** SALVA STATO COMANDO NEL DATABASE ***
      // Assumendo che IAgentData abbia metodi per aggiornare lo stato del comando
      try
        // Metodo principale per completare il comando
        //FAgentData.SendCommandComplete(ACommandId, AExitCode);
        FAgentData.OnMethod(COMMAND_COMPLETED, TgrBsonDocument.Create
            .Add('machine_id', FAgentId)
            .Add('command_id', ACommandId)
            .Add('exit_code', AExitCode));
        WriteLn(Format('[OutputHandler] Command %s status updated in database: %s',
          [ACommandId, Status]));
      except
        on E: Exception do
          WriteLn(Format('[OutputHandler] Error updating command %s status: %s',
            [ACommandId, E.Message]));
      end;
    end;
  finally
    FLock.Leave;
  end;
end;


procedure TOutputHandler.HandleValidationError(const ACommandId, ASessionId: string;
  const ACommand, AErrorMessage: string);
var
  messagerror:string;
begin
  FLock.Enter;
  try
    WriteLn(Format('[OutputHandler] Handling validation error for command %s', [ACommandId]));

    if Assigned(FAgentData) then
    begin
    messagerror:='========================================\n';
    messagerror:= messagerror + 'COMMAND VALIDATION FAILED';
    messagerror:= messagerror + Format(' \nCommand: %s', [ACommand]);
    messagerror:= messagerror + Format(' \nReason: %s', [AErrorMessage]);
    messagerror:=messagerror+' \n========================================';
      // 1. Invia messaggio di errore alla sessione
      //FAgentData.SendOutput(FAgentId, ASessionId, 'stderr',
      //  '========================================');
      FAgentData.OnMethod(COMMAND_OUTPUT, TgrBsonDocument.Create
            .Add('machine_id', FAgentId)
            .Add('session_id', ASessionId)
            .Add('command_id', ACommandId)
            .Add('stream', 'stderr')
            .Add('data', messagerror)
            .Add('timestamp', DateToISO8601(Now, True)));

      // 2. Aggiorna stato comando nel database come fallito
      try
        //FAgentData.SendCommandComplete(ACommandId, EXIT_CODE_VALIDATION_ERROR);

        FAgentData.OnMethod(COMMAND_COMPLETED, TgrBsonDocument.Create
            .Add('machine_id', FAgentId)
            .Add('command_id', ACommandId)
            .Add('exit_code', EXIT_CODE_VALIDATION_ERROR));

        WriteLn(Format('[OutputHandler] Command %s marked as validation failed in database',
          [ACommandId]));
      except
        on E: Exception do
          WriteLn(Format('[OutputHandler] Error marking command %s as failed: %s',
            [ACommandId, E.Message]));
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

// *** NUOVO METODO per gestire errori di esecuzione ***
procedure TOutputHandler.HandleExecutionError(const ACommandId, ASessionId: string;
  const ACommand, AErrorMessage: string);
var
  messagerror:string;
begin
  FLock.Enter;
  try
    WriteLn(Format('[OutputHandler] Handling execution error for command %s', [ACommandId]));

    if Assigned(FAgentData) then
    begin
    messagerror:='========================================\n';
    messagerror:= messagerror + 'COMMAND EXECUTION FAILED';
    messagerror:= messagerror + Format(' \nCommand: %s', [ACommand]);
    messagerror:= messagerror + Format(' \Error: %s', [AErrorMessage]);
    messagerror:=messagerror+' \n========================================';
      // 1. Invia messaggio di errore alla sessione
      FAgentData.OnMethod(COMMAND_OUTPUT, TgrBsonDocument.Create
            .Add('machine_id', FAgentId)
            .Add('session_id', ASessionId)
            .Add('command_id', ACommandId)
            .Add('stream', 'stderr')
            .Add('data', messagerror)
            .Add('timestamp', DateToISO8601(Now, True)));
      // 2. Aggiorna stato comando nel database come fallito
      try
        //FAgentData.SendCommandComplete(ACommandId, EXIT_CODE_EXECUTION_ERROR);

        FAgentData.OnMethod(COMMAND_COMPLETED, TgrBsonDocument.Create
            .Add('machine_id', FAgentId)
            .Add('command_id', ACommandId)
            .Add('exit_code', EXIT_CODE_EXECUTION_ERROR));

        WriteLn(Format('[OutputHandler] Command %s marked as execution failed in database',
          [ACommandId]));
      except
        on E: Exception do
          WriteLn(Format('[OutputHandler] Error marking command %s as failed: %s',
            [ACommandId, E.Message]));
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

{ TShellExecutor }

constructor TShellExecutor.Create(const ASessionRepository: ISessionRepository;
  const AShellRunnerFactory: IShellRunnerFactory);
begin
  inherited Create;
  FSessionRepository := ASessionRepository;
  FShellRunnerFactory := AShellRunnerFactory;
  FRunningCommands := TDictionary<string, TRunningCommandInfo>.Create;
  FRunningBySession := TDictionary<string, string>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TShellExecutor.Destroy;
begin
  FRunningCommands.Free;
  FLock.Free;
  inherited;
end;

procedure TShellExecutor.ExecuteCommand(const ASessionId: string;
 const CommandId : string; const ACommand: string);
var
  ShellSession: IShellSession;
  CommandInfo: TRunningCommandInfo;
begin
  FLock.Enter;
  try
    if FRunningCommands.ContainsKey(CommandId) then
      raise Exception.Create('Comando già in esecuzione per questa sessione');

    ShellSession := (FSessionRepository as TSessionRepository).GetShellSession(ASessionId);
    if not Assigned(ShellSession) then
      raise Exception.Create('Sessione non trovata');

    CommandInfo.CommandId := CommandId;
    CommandInfo.SessionId := ASessionId;
    CommandInfo.StartTime := Now;
    CommandInfo.CommandText := ACommand;
    FRunningCommands.Add(CommandId, CommandInfo);
    FRunningBySession.Add(ASessionId, CommandId);

    WriteLn(Format('[ShellExecutor] Starting command %s on session %s: %s',
      [CommandId, ASessionId, ACommand]));
  finally
    FLock.Leave;
  end;

  try
    // Configura callbacks
    ShellSession.OnOutput := // OnOutput callback
      procedure(const Line: string)
      begin
        FOutputHandler.HandleOutput(ASessionId, CommandId, Line);
      end;

    ShellSession.OnError := procedure(const Line: string)
      begin
        FOutputHandler.HandleError(ASessionId, CommandId, Line);
      end;

    ShellSession.OnExit := procedure(const ExitCode: Integer)
    begin
      CleanupCommand(CommandId);  // Cleanup centralizzato
      FOutputHandler.HandleCommandComplete(CommandId, ExitCode);
      WriteLn(Format('[ShellExecutor] Command %s completed with exit code %d',
            [CommandId, ExitCode]));
    end;

    // Esegui comando
    ShellSession.ExecuteCommand(ACommand);
    FSessionRepository.UpdateSessionActivity(ASessionId);
  except
    FLock.Enter;
    try
       CleanupCommand(CommandId);
    finally
      FLock.Leave;
    end;
    raise;
  end;
end;

procedure TShellExecutor.CleanupCommand(const ACommandId: string);
var
  CommandInfo: TRunningCommandInfo;
  Duration: Double;
begin
  FLock.Enter;
  try
    if FRunningCommands.TryGetValue(ACommandId, CommandInfo) then
    begin
      Duration := (Now - CommandInfo.StartTime) * 24 * 60 * 60; // secondi
      WriteLn(Format('[ShellExecutor] Command %s completed in %.2f seconds',
        [ACommandId, Duration]));

      // Rimuovi da entrambe le strutture
      FRunningCommands.Remove(ACommandId);
      FRunningBySession.Remove(CommandInfo.SessionId);
    end;
  finally
    FLock.Leave;
  end;
end;

function TShellExecutor.IsCommandRunning(const ACommandId: string): Boolean;
begin
  FLock.Enter;
  try
    Result := FRunningCommands.ContainsKey(ACommandId);
  finally
    FLock.Leave;
  end;
end;

function TShellExecutor.IsSessionBusy(const ASessionId: string): Boolean;
begin
  FLock.Enter;
  try
    Result := FRunningBySession.ContainsKey(ASessionId);
  finally
    FLock.Leave;
  end;
end;

function TShellExecutor.GetRunningCommandForSession(const ASessionId: string): string;
begin
  FLock.Enter;
  try
    if not FRunningBySession.TryGetValue(ASessionId, Result) then
      Result := '';
  finally
    FLock.Leave;
  end;
end;

procedure TShellExecutor.CancelCommand(const ASessionId: string);
var
  ShellSession: IShellSession;
begin
  FLock.Enter;
  try
    if not FRunningCommands.ContainsKey(ASessionId) then
      Exit;

    ShellSession := (FSessionRepository as TSessionRepository).GetShellSession(ASessionId);
    if Assigned(ShellSession) then
      ShellSession.StopSession;

    FRunningCommands.Remove(ASessionId);
  finally
    FLock.Leave;
  end;
end;

procedure TShellExecutor.SetOutputHandler(const AHandler: IOutputHandler);
begin
  FOutputHandler := AHandler;
end;

{ TSessionRepository }

constructor TSessionRepository.Create(const AShellFactory: IShellRunnerFactory);
begin
  inherited Create;
  FShellFactory := AShellFactory;
  FSessions := TDictionary<string, TSessionInfo>.Create;
  FShellSessions := TDictionary<string, IShellSession>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TSessionRepository.Destroy;
begin
  //CloseAllSessions;
  FSessions.Free;
  FShellSessions.Free;
  FLock.Free;
  inherited;
end;

function TSessionRepository.GenerateSessionId: string;
var
  GUID: TGUID;
begin
  CreateGUID(GUID);
  Result := 'session_' + GUIDToString(GUID).Replace('{', '').Replace('}', '').Replace('-', '').ToLower.Substring(0, 16);
end;

function TSessionRepository.CreateSession(const AShellType: string; const ASessionId: string): TSessionInfo;
var
  Id: string;
  ShellSession: IShellSession;
begin
  FLock.Enter;
  try
    Id := ASessionId;
    if Id.Trim.IsEmpty then
      Id := GenerateSessionId;

    if FSessions.ContainsKey(Id) then
      raise Exception.CreateFmt('Sessione già esistente: %s', [Id]);

    ShellSession := TShellSession.Create(Id, AShellType, FShellFactory);

    Result.SessionId := Id;
    Result.ShellType := AShellType;
    Result.CreatedAt := Now;
    Result.LastActivity := Now;
    Result.IsActive := True;
    Result.CommandCount := 0;

    FSessions.Add(Id, Result);
    FShellSessions.Add(Id, ShellSession);
  finally
    FLock.Leave;
  end;
end;

function TSessionRepository.GetSession(const ASessionId: string): TSessionInfo;
begin
  FLock.Enter;
  try
    if not FSessions.TryGetValue(ASessionId, Result) then
      raise Exception.CreateFmt('Sessione non trovata: %s', [ASessionId]);
  finally
    FLock.Leave;
  end;
end;

function TSessionRepository.GetShellSession(const ASessionId: string): IShellSession;
begin
  FLock.Enter;
  try
    if not FShellSessions.TryGetValue(ASessionId, Result) then
      Result := nil;
  finally
    FLock.Leave;
  end;
end;

function TSessionRepository.GetAllSessions: TArray<TSessionInfo>;
begin
  FLock.Enter;
  try
    Result := FSessions.Values.ToArray;
  finally
    FLock.Leave;
  end;
end;

function TSessionRepository.SessionExists(const ASessionId: string): Boolean;
begin
  FLock.Enter;
  try
    Result := FSessions.ContainsKey(ASessionId);
  finally
    FLock.Leave;
  end;
end;

procedure TSessionRepository.UpdateSessionActivity(const ASessionId: string);
var
  Info: TSessionInfo;
begin
  FLock.Enter;
  try
    if FSessions.TryGetValue(ASessionId, Info) then
    begin
      Info.LastActivity := Now;
      Info.CommandCount := Info.CommandCount + 1;
      FSessions.AddOrSetValue(ASessionId, Info);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TSessionRepository.CloseSession(const ASessionId: string);
var
  ShellSession: IShellSession;
begin
  FLock.Enter;
  try
    if FShellSessions.TryGetValue(ASessionId, ShellSession) then
    begin
      ShellSession.StopSession;
      FShellSessions.Remove(ASessionId);
    end;
    FSessions.Remove(ASessionId);
  finally
    FLock.Leave;
  end;
end;

procedure TSessionRepository.CloseAllSessions;
var
  SessionIds: TArray<string>;
  Id: string;
begin
  FLock.Enter;
  try
    SessionIds := FSessions.Keys.ToArray;
  finally
    FLock.Leave;
  end;

  for Id in SessionIds do
    CloseSession(Id);
end;

function TSessionRepository.GetActiveSessionCount: Integer;
begin
  FLock.Enter;
  try
    Result := FSessions.Count;
  finally
    FLock.Leave;
  end;
end;

procedure TSessionRepository.CleanupInactiveSessions(const ATimeoutMinutes: Integer);
var
  ToRemove: TList<string>;
  Pair: TPair<string, TSessionInfo>;
  TimeoutTime: TDateTime;
begin
  ToRemove := TList<string>.Create;
  try
    TimeoutTime := IncMinute(Now, -ATimeoutMinutes);

    FLock.Enter;
    try
      for Pair in FSessions do
      begin
        if Pair.Value.LastActivity < TimeoutTime then
          ToRemove.Add(Pair.Key);
      end;
    finally
      FLock.Leave;
    end;

    for var Id in ToRemove do
      CloseSession(Id);
  finally
    ToRemove.Free;
  end;
end;

{ TShellSessionService }

constructor TShellSessionService.Create(const AValidator: ICommandValidator;
  const ALimiter: ISessionLimiter; const AExecutor: IShellExecutor;
  const ARepository: ISessionRepository; const AOutputHandler: IOutputHandler);
begin
  inherited Create;
  FValidator := AValidator;
  FLimiter := ALimiter;
  FExecutor := AExecutor;
  FRepository := ARepository;
  FOutputHandler := AOutputHandler;
  FLock := TCriticalSection.Create;

  FExecutor.SetOutputHandler(FOutputHandler);
end;

destructor TShellSessionService.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TShellSessionService.CreateSession(const AShellType: string; const ASessionId: string): TSessionInfo;
begin
  FLock.Enter;
  try
    if not FLimiter.CanCreateSession then
      raise Exception.CreateFmt('Limite sessioni raggiunto (%d/%d)',
        [FLimiter.GetActiveSessionCount, FLimiter.GetMaxSessions]);

    Result := FRepository.CreateSession(AShellType, ASessionId);
  finally
    FLock.Leave;
  end;
end;

function TShellSessionService.ExecuteCommand(const ASessionId: string; const CommandId : string;
 const ACommand: string): TCommandExecutionResult;
var
  ValidationResult: TCommandValidationResult;
  StartTime: TDateTime;
begin
  Result := TCommandExecutionResult.Create(False);

  FLock.Enter;
  try
     WriteLn(Format('[ShellSessionService] Execute request - Session: %s, Command: %s, Text: "%s"',
      [ASessionId, CommandId, ACommand]));
    // Verifica esistenza sessione
    if not FRepository.SessionExists(ASessionId) then
    begin
      Result.ErrorMessage := Format('Sessione non trovata: %s', [ASessionId]);
      WriteLn(Format('[ShellSessionService] ERROR: %s', [Result.ErrorMessage]));
      Exit;
    end;

    // Verifica comando già in esecuzione (ora usa la logica corretta)
    if FExecutor.IsCommandRunning(CommandId) then
    begin
      Result.ErrorMessage := Format('Comando MongoDB %s già in esecuzione', [CommandId]);
      WriteLn(Format('[ShellSessionService] ERROR: %s', [Result.ErrorMessage]));
      Exit;
    end;
  finally
    FLock.Leave;
  end;

  ValidationResult := FValidator.ValidateCommand(ACommand);
  if not ValidationResult.IsValid then
  begin
    WriteLn(Format('[ShellSessionService] VALIDATION FAILED: %s', [ValidationResult.ErrorMessage]));

    HandleValidationFailure(ASessionId, CommandId, ACommand, ValidationResult.ErrorMessage, StartTime);

    // Imposta risultato per il chiamante
    Result.ErrorMessage := ValidationResult.ErrorMessage;
    Result.ExecutionTime := (Now - StartTime) * 24 * 60 * 60;
    Result.Success := False; // Comando "processato" ma fallito
    Exit;
  end;

  StartTime := Now;
  try
    FExecutor.ExecuteCommand(ASessionId, CommandId, ACommand);

    Result.Success := True;
    Result.ExecutionTime := (Now - StartTime) * 24 * 60 * 60;

    WriteLn(Format('[ShellSessionService] Command %s execution started successfully', [CommandId]));
  except
    on E: Exception do
    begin
      WriteLn(Format('[ShellSessionService] Command %s execution failed: %s', [CommandId, E.Message]));

      HandleExecutionFailure(ASessionId, CommandId, ACommand, E.Message, StartTime);

      Result.ErrorMessage := E.Message;
      Result.ExecutionTime := (Now - StartTime) * 24 * 60 * 60;
      Result.Success := False;
    end;
  end;
end;

// Gestisce fallimenti di validazione
procedure TShellSessionService.HandleValidationFailure(
  const ASessionId, ACommandId, ACommand, AErrorMessage: string;
  const AStartTime: TDateTime);
begin
  WriteLn(Format('[ShellSessionService] Handling validation failure for command %s', [ACommandId]));

  try
    // 1. Invia output di errore alla sessione
    if Assigned(FOutputHandler) then
    begin
      FOutputHandler.HandleError(ASessionId, ACommandId,
        Format('VALIDATION ERROR: %s', [AErrorMessage]));
      FOutputHandler.HandleError(ASessionId, ACommandId,
        Format('Command rejected: "%s"', [ACommand]));
    end;

    // 2. Aggiorna attività sessione
    FRepository.UpdateSessionActivity(ASessionId);

    // 3. Notifica completamento comando con exit code di errore (es: 403 per Forbidden)
    if Assigned(FOutputHandler) then
    begin
      WriteLn(Format('[ShellSessionService] Completing command %s with validation error', [ACommandId]));
      FOutputHandler.HandleCommandComplete(ACommandId, 403); // 403 = Forbidden/Unauthorized
    end;

  except
    on E: Exception do
      WriteLn(Format('[ShellSessionService] Error handling validation failure: %s', [E.Message]));
  end;
end;

procedure TShellSessionService.HandleExecutionFailure(
  const ASessionId, ACommandId, ACommand, AErrorMessage: string;
  const AStartTime: TDateTime);
begin
  WriteLn(Format('[ShellSessionService] Handling execution failure for command %s', [ACommandId]));

  try
    // 1. Invia output di errore
    if Assigned(FOutputHandler) then
    begin
      FOutputHandler.HandleError(ASessionId, ACommandId,
        Format('EXECUTION ERROR: %s', [AErrorMessage]));
    end;

    // 2. Aggiorna attività sessione
    FRepository.UpdateSessionActivity(ASessionId);

    // 3. Notifica completamento comando con exit code di errore
    if Assigned(FOutputHandler) then
    begin
      WriteLn(Format('[ShellSessionService] Completing command %s with execution error', [ACommandId]));
      FOutputHandler.HandleCommandComplete(ACommandId, 500); // 500 = Internal Error
    end;

  except
    on E: Exception do
      WriteLn(Format('[ShellSessionService] Error handling execution failure: %s', [E.Message]));
  end;
end;

function TShellSessionService.GetSession(const ASessionId: string): TSessionInfo;
begin
  Result := FRepository.GetSession(ASessionId);
end;

function TShellSessionService.GetAllSessions: TArray<TSessionInfo>;
begin
  Result := FRepository.GetAllSessions;
end;

procedure TShellSessionService.CloseSession(const ASessionId: string);
begin
  FRepository.CloseSession(ASessionId);
end;

procedure TShellSessionService.CloseAllSessions;
begin
  FRepository.CloseAllSessions;
end;

function TShellSessionService.GetServiceStats: TJSONObject;
var
  Sessions: TArray<TSessionInfo>;
  Session: TSessionInfo;
  SessionArray: TJSONArray;
  SessionObj: TJSONObject;
  TotalCommands: Integer;
begin
  Result := TJSONObject.Create;
  SessionArray := TJSONArray.Create;
  Sessions := GetAllSessions;
  TotalCommands := 0;

  for Session in Sessions do
  begin
    SessionObj := TJSONObject.Create;
    SessionObj.AddPair('sessionId', Session.SessionId);
    SessionObj.AddPair('shellType', Session.ShellType);
    SessionObj.AddPair('createdAt', DateToISO8601(Session.CreatedAt));
    SessionObj.AddPair('lastActivity', DateToISO8601(Session.LastActivity));
    SessionObj.AddPair('isActive', TJSONBool.Create(Session.IsActive));
    SessionObj.AddPair('commandCount', TJSONNumber.Create(Session.CommandCount));
    SessionArray.Add(SessionObj);

    TotalCommands := TotalCommands + Session.CommandCount;
  end;

  Result.AddPair('sessions', SessionArray);
  Result.AddPair('totalSessions', TJSONNumber.Create(Length(Sessions)));
  Result.AddPair('activeSessions', TJSONNumber.Create(FLimiter.GetActiveSessionCount));
  Result.AddPair('maxSessions', TJSONNumber.Create(FLimiter.GetMaxSessions));
  Result.AddPair('totalCommands', TJSONNumber.Create(TotalCommands));
end;

end.
