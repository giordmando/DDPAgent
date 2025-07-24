unit RMC.ShellServiceFactory;

interface

uses
  System.SysUtils, AgentServiceI, RMC.Data, Shell.Interfaces, RMC.ShellServiceImplementations;

type
  // Factory per creare il servizio completo
  TShellServiceFactory = class
  private
    FAgentId: string;
    FValidator: ICommandValidator;
    FShellRunnerFactory: IShellRunnerFactory;
    FMaxSessions: Integer;
    FAuthRulesFile: string;

  public

  function CreateShellSessionService(
      const AAgentData: IAgentData
      ): IShellSessionService;

  procedure RegisterShellSessionService(
    const AAgentId: string;
    const AShellRunnerFactory: IShellRunnerFactory;
    const AValidator:ICommandValidator;
    const AMaxSessions: Integer = 10;
    const AAuthRulesFile: string = ''
    );
  end;

implementation

{ TShellServiceFactory }

procedure TShellServiceFactory.RegisterShellSessionService(
  const AAgentId: string;
  const AShellRunnerFactory: IShellRunnerFactory;
  const AValidator:ICommandValidator;
  const AMaxSessions: Integer;
  const AAuthRulesFile: string
  );

begin
  // Crea le dipendenze nell'ordine corretto
  FAgentId := AAgentId;
  FValidator := AValidator;
  FShellRunnerFactory := AShellRunnerFactory;
  FMaxSessions := AMaxSessions;
  FAuthRulesFile := AAuthRulesFile;

  // Crea il servizio principale
  //Result := TShellSessionService.Create(Validator, Limiter, Executor, Repository, OutputHandler);
end;

function TShellServiceFactory.CreateShellSessionService(
  const AAgentData: IAgentData): IShellSessionService;
var
  Validator: ICommandValidator;
  Repository: ISessionRepository;
  Limiter: ISessionLimiter;
  OutputHandler: IOutputHandler;
  Executor: IShellExecutor;
begin
  // Crea le dipendenze nell'ordine corretto
  Validator := FValidator;
  Repository := TSessionRepository.Create(FShellRunnerFactory);
  Limiter := TSessionLimiter.Create(Repository, FMaxSessions);
  OutputHandler := TOutputHandler.Create(FAgentId, AAgentData);
  Executor := TShellExecutor.Create(Repository, FShellRunnerFactory);

  // Carica regole di autorizzazione se fornite
  if (FAuthRulesFile <> '') and FileExists(FAuthRulesFile) then
    Validator.LoadRules(FAuthRulesFile)
  else
  begin
    // Configura autorizzazioni
    Validator.AddToWhitelist('dir*');
    Validator.AddToWhitelist('cd*');
    Validator.AddToWhitelist('help*');
    Validator.AddToWhitelist('ping*');
    Validator.AddToWhitelist('echo*');
    Validator.AddToWhitelist('whoami*');
    Validator.AddToWhitelist('date*');
    Validator.AddToWhitelist('ipconfig*');
    Validator.AddToWhitelist('history*');

    Validator.AddToBlacklist('format*');
    Validator.AddToBlacklist('del /s*');
  end;

  // Crea il servizio principale
  Result := TShellSessionService.Create(Validator, Limiter, Executor, Repository, OutputHandler);
end;

end.
