unit RMC.ShellServiceInterfaces;

interface

uses
  System.SysUtils, System.Classes, System.JSON, AgentServiceI;

type
  // Risultato di validazione comando
  TCommandValidationResult = record
    IsValid: Boolean;
    ErrorMessage: string;
    class function Success: TCommandValidationResult; static;
    class function Failure(const AErrorMessage: string)
      : TCommandValidationResult; static;
  end;

  // Risultato di esecuzione comando
  TCommandExecutionResult = record
    Success: Boolean;
    ExitCode: Integer;
    Output: TStrings;
    ErrorOutput: TStrings;
    ExecutionTime: Double;
    ErrorMessage: string;
    constructor Create(ASuccess: Boolean; AExitCode: Integer = 0;
      const AErrorMessage: string = '');
  end;

  // Info sessione semplificata
  TSessionInfo = record
    SessionId: string;
    ShellType: string;
    CreatedAt: TDateTime;
    LastActivity: TDateTime;
    IsActive: Boolean;
    CommandCount: Integer;
  end;

  // Forward declarations
  ICommandValidator = interface;
  ISessionLimiter = interface;
  IOutputHandler = interface;
  IShellExecutor = interface;
  ISessionRepository = interface;
  IShellSessionService = interface;

  // Valida i comandi contro whitelist/blacklist
  ICommandValidator = interface
    function ValidateCommand(const ACommand: string): TCommandValidationResult;
    procedure LoadRules(const ASource: string);
    procedure AddToWhitelist(const ACommandPattern: string);
    procedure AddToBlacklist(const ACommandPattern: string);
    procedure Clear;
  end;

  // Gestisce i limiti delle sessioni
  ISessionLimiter = interface
    function CanCreateSession: Boolean;
    function GetMaxSessions: Integer;
    function GetActiveSessionCount: Integer;
    procedure SetMaxSessions(const AValue: Integer);
  end;

  // Gestisce l'output dei comandi
  IOutputHandler = interface
    procedure HandleOutput(const ASessionId: string; const CommandId: string; const ALine: string);
    procedure HandleError(const ASessionId: string; const CommandId: string; const ALine: string);
    procedure HandleCommandComplete(const ACommandId: string;
      const AExitCode: Integer);
    procedure HandleValidationError(const ACommandId, ASessionId: string;
      const ACommand, AErrorMessage: string);
    procedure HandleExecutionError(const ACommandId, ASessionId: string;
      const ACommand, AErrorMessage: string);
  end;

  // Esegue comandi nella shell
  IShellExecutor = interface
    procedure ExecuteCommand(const ASessionId: string; const CommandId : string; const ACommand: string);
    function IsCommandRunning(const ASessionId: string): Boolean;
    procedure CancelCommand(const ASessionId: string);
    procedure SetOutputHandler(const AHandler: IOutputHandler);
  end;

  // Repository per le sessioni
  ISessionRepository = interface
    function CreateSession(const AShellType: string;
      const ASessionId: string = ''): TSessionInfo;
    function GetSession(const ASessionId: string): TSessionInfo;
    function GetAllSessions: TArray<TSessionInfo>;
    function SessionExists(const ASessionId: string): Boolean;
    procedure UpdateSessionActivity(const ASessionId: string);
    procedure CloseSession(const ASessionId: string);
    procedure CloseAllSessions;
    function GetActiveSessionCount: Integer;
    procedure CleanupInactiveSessions(const ATimeoutMinutes: Integer);
  end;

  // Servizio principale che orchestra tutto
  IShellSessionService = interface
    function CreateSession(const AShellType: string;
      const ASessionId: string = ''): TSessionInfo;
    function ExecuteCommand(const ASessionId: string; const CommandId : string; const ACommand: string)
      : TCommandExecutionResult;
    function GetSession(const ASessionId: string): TSessionInfo;
    function GetAllSessions: TArray<TSessionInfo>;
    procedure CloseSession(const ASessionId: string);
    procedure CloseAllSessions;
    function GetServiceStats: TJSONObject;

    procedure HandleValidationFailure(const ASessionId, ACommandId, ACommand, AErrorMessage: string; const AStartTime: TDateTime);
    procedure HandleExecutionFailure(const ASessionId, ACommandId, ACommand, AErrorMessage: string; const AStartTime: TDateTime);

  end;

implementation

{ TCommandValidationResult }

class function TCommandValidationResult.Success: TCommandValidationResult;
begin
  Result.IsValid := True;
  Result.ErrorMessage := '';
end;

class function TCommandValidationResult.Failure(const AErrorMessage: string)
  : TCommandValidationResult;
begin
  Result.IsValid := False;
  Result.ErrorMessage := AErrorMessage;
end;

{ TCommandExecutionResult }

constructor TCommandExecutionResult.Create(ASuccess: Boolean;
  AExitCode: Integer; const AErrorMessage: string);
begin
  Success := ASuccess;
  ExitCode := AExitCode;
  ErrorMessage := AErrorMessage;
  Output := TStringList.Create;
  ErrorOutput := TStringList.Create;
  ExecutionTime := 0;
end;

end.
