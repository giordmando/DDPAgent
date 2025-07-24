unit Shell.Interfaces;

interface
uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.JSON,
  System.Threading;

type
  TOutputProc = reference to procedure(const Line: string);
  TExitCodeProc = reference to procedure(const ExitCode: Integer);

  // ===== INTERFACCE DI SESSIONE =====

  // Interfaccia per shell runner
  IShellRunner = interface
    procedure ExecuteCommand(
      const Command: string;
      const OnOutput: TOutputProc;
      const OnError: TOutputProc;
      const OnExit: TExitCodeProc
    );
    procedure StopExecution;
    function IsRunning: Boolean;
    function GetWorkingDirectory: string;
    procedure SetWorkingDirectory(const Dir: string);
  end;

  // Interfaccia per sessione shell
  IShellSession = interface
    procedure ExecuteCommand(const Command: string);
    procedure StopSession;

    function GetSessionId: string;
    function GetShellType: string;
    function GetCreatedAt: TDateTime;
    function GetLastActivity: TDateTime;
    function IsActive: Boolean;

    function GetOnOutput: TOutputProc;
    procedure SetOnOutput(const Value: TOutputProc);
    function GetOnError: TOutputProc;
    procedure SetOnError(const Value: TOutputProc);
    function GetOnExit: TExitCodeProc;
    procedure SetOnExit(const Value: TExitCodeProc);

    property SessionId: string read GetSessionId;
    property ShellType: string read GetShellType;
    property CreatedAt: TDateTime read GetCreatedAt;
    property LastActivity: TDateTime read GetLastActivity;
    property OnOutput: TOutputProc read GetOnOutput write SetOnOutput;
    property OnError: TOutputProc read GetOnError write SetOnError;
    property OnExit: TExitCodeProc read GetOnExit write SetOnExit;
  end;

  // Factory per shell runner
  IShellRunnerFactory = interface
    function CreateRunner(const ShellType: string): IShellRunner;
  end;

// Command validation result
  TCommandValidationResult = record
    IsValid: Boolean;
    ErrorMessage: string;
    class function Success: TCommandValidationResult; static;
    class function Failure(const AErrorMessage: string): TCommandValidationResult; static;
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

  // Session info
  TSessionInfo = record
    SessionId: string;
    ShellType: string;
    CreatedAt: TDateTime;
    LastActivity: TDateTime;
    IsActive: Boolean;
    CommandCount: Integer;
  end;

  // Command validator interface
  ICommandValidator = interface
    ['{12345678-1234-1234-1234-123456789043}']
    function ValidateCommand(const ACommand: string): TCommandValidationResult;
    procedure LoadRules(const ASource: string);
    procedure AddToWhitelist(const ACommandPattern: string);
    procedure AddToBlacklist(const ACommandPattern: string);
    procedure Clear;
  end;

  // Session repository interface
  ISessionRepository = interface
    ['{12345678-1234-1234-1234-123456789044}']
    function CreateSession(const AShellType: string; const ASessionId: string = ''): TSessionInfo;
    function GetSession(const ASessionId: string): TSessionInfo;
    function GetAllSessions: TArray<TSessionInfo>;
    function SessionExists(const ASessionId: string): Boolean;
    procedure UpdateSessionActivity(const ASessionId: string);
    procedure CloseSession(const ASessionId: string);
    procedure CloseAllSessions;
    function GetActiveSessionCount: Integer;
  end;

  // Output handler interface
  IOutputHandler = interface
    ['{12345678-1234-1234-1234-123456789045}']
    procedure HandleOutput(const ASessionId: string; const CommandId: string; const ALine: string);
    procedure HandleError(const ASessionId: string; const CommandId: string; const ALine: string);
    procedure HandleCommandComplete(const ACommandId: string; const AExitCode: Integer);
    procedure HandleValidationError(const ACommandId, ASessionId: string; const ACommand, AErrorMessage: string);
    procedure HandleExecutionError(const ACommandId, ASessionId: string; const ACommand, AErrorMessage: string);
  end;

  // Session limiter interface
  ISessionLimiter = interface
    ['{12345678-1234-1234-1234-123456789046}']
    function CanCreateSession: Boolean;
    function GetMaxSessions: Integer;
    function GetActiveSessionCount: Integer;
    procedure SetMaxSessions(const AValue: Integer);
  end;

  // Shell executor interface
  IShellExecutor = interface
    ['{12345678-1234-1234-1234-123456789047}']
    procedure ExecuteCommand(const ASessionId: string; const CommandId: string; const ACommand: string);
    function IsCommandRunning(const ASessionId: string): Boolean;
    procedure CancelCommand(const ASessionId: string);
    procedure SetOutputHandler(const AHandler: IOutputHandler);
  end;

  // Main shell session service interface
  IShellSessionService = interface
    function CreateSession(const AShellType: string; const ASessionId: string = ''): TSessionInfo;
    function ExecuteCommand(const ASessionId: string; const CommandId: string; const ACommand: string): TCommandExecutionResult;
    function GetSession(const ASessionId: string): TSessionInfo;
    function GetAllSessions: TArray<TSessionInfo>;
    procedure CloseSession(const ASessionId: string);
    procedure CloseAllSessions;
    function GetServiceStats: TJSONObject;
    procedure HandleValidationFailure(const ASessionId, ACommandId, ACommand, AErrorMessage: string; const AStartTime: TDateTime);
    procedure HandleExecutionFailure(const ASessionId, ACommandId, ACommand, AErrorMessage: string; const AStartTime: TDateTime);
  end;

  // Interfaccia autorizzazione
  IAuthManager = interface
    function IsAuthorized(const SessionId, Command: string): Boolean;
    procedure AddToWhitelist(const CommandPattern: string);
    procedure AddToBlacklist(const CommandPattern: string);
    procedure LoadRules(const Source: string);
  end;

implementation

{ TCommandValidationResult }

class function TCommandValidationResult.Success: TCommandValidationResult;
begin
  Result.IsValid := True;
  Result.ErrorMessage := '';
end;

class function TCommandValidationResult.Failure(const AErrorMessage: string): TCommandValidationResult;
begin
  Result.IsValid := False;
  Result.ErrorMessage := AErrorMessage;
end;

{ TCommandExecutionResult }

constructor TCommandExecutionResult.Create(ASuccess: Boolean; AExitCode: Integer; const AErrorMessage: string);
begin
  Success := ASuccess;
  ExitCode := AExitCode;
  ErrorMessage := AErrorMessage;
  Output := TStringList.Create;
  ErrorOutput := TStringList.Create;
  ExecutionTime := 0;
end;

end.
