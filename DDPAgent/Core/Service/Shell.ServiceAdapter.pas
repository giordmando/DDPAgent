unit Shell.ServiceAdapter;

interface

uses
  System.SysUtils, System.JSON, Core.ServiceInterfaces,
  Shell.Interfaces; // Your existing shell interfaces

type
  // ADAPTER: Shell service che implementa entrambe le interfacce
  TShellServiceAdapter = class(TInterfacedObject, IApplicationService, IShellSessionService)
  private
    FShellService: IShellSessionService; // Tuo servizio shell esistente
    FIsRunning: Boolean;
  protected
    // IApplicationService implementation (generic)
    function GetServiceName: string;
    function GetServiceVersion: string;
    function GetServiceNamespace: string;

    procedure Initialize;
    procedure Start;
    procedure Stop;
    procedure Shutdown;
    function IsRunning: Boolean;

    function GetServiceStats: TJSONObject;
    function IsHealthy: Boolean;
    function GetHealthStatus: string;

    // IShellSessionService implementation (delegate to real service)
    function CreateSession(const AShellType: string; const ASessionId: string = ''): TSessionInfo;
    function ExecuteCommand(const ASessionId: string; const CommandId: string; const ACommand: string): TCommandExecutionResult;
    function GetSession(const ASessionId: string): TSessionInfo;
    function GetAllSessions: TArray<TSessionInfo>;
    procedure CloseSession(const ASessionId: string);
    procedure CloseAllSessions;
    function GetShellServiceStats: TJSONObject; // Renamed to avoid conflict
    procedure HandleValidationFailure(const ASessionId, ACommandId, ACommand, AErrorMessage: string; const AStartTime: TDateTime);
    procedure HandleExecutionFailure(const ASessionId, ACommandId, ACommand, AErrorMessage: string; const AStartTime: TDateTime);
  public
    constructor Create(const AShellService: IShellSessionService);
  end;

implementation

constructor TShellServiceAdapter.Create(const AShellService: IShellSessionService);
begin
  inherited Create;
  FShellService := AShellService;
  FIsRunning := False;
end;

// IApplicationService implementation
function TShellServiceAdapter.GetServiceName: string;
begin
  Result := 'Shell Command Service';
end;

function TShellServiceAdapter.GetServiceVersion: string;
begin
  Result := '1.0.0';
end;

function TShellServiceAdapter.GetServiceNamespace: string;
begin
  Result := 'shell';
end;

procedure TShellServiceAdapter.Initialize;
begin
  // Initialize if needed
  WriteLn('[Shell Service] Initializing...');
end;

procedure TShellServiceAdapter.Start;
begin
  FIsRunning := True;
  WriteLn('[Shell Service] Started');
end;

procedure TShellServiceAdapter.Stop;
begin
  if Assigned(FShellService) then
    FShellService.CloseAllSessions;
  FIsRunning := False;
  WriteLn('[Shell Service] Stopped');
end;

procedure TShellServiceAdapter.Shutdown;
begin
  Stop;
  WriteLn('[Shell Service] Shutdown complete');
end;

function TShellServiceAdapter.IsRunning: Boolean;
begin
  Result := FIsRunning;
end;

function TShellServiceAdapter.GetServiceStats: TJSONObject;
begin
  if Assigned(FShellService) then
    Result := FShellService.GetServiceStats
  else
    Result := TJSONObject.Create;
end;

function TShellServiceAdapter.IsHealthy: Boolean;
begin
  Result := FIsRunning and Assigned(FShellService);
end;

function TShellServiceAdapter.GetHealthStatus: string;
begin
  if IsHealthy then
    Result := 'Healthy'
  else
    Result := 'Unhealthy';
end;

//IShellSessionService implementation (delegation)
function TShellServiceAdapter.CreateSession(const AShellType: string; const ASessionId: string): TSessionInfo;
begin
  if Assigned(FShellService) then
    Result := FShellService.CreateSession(AShellType, ASessionId)
  else
    raise Exception.Create('Shell service not available');
end;

function TShellServiceAdapter.ExecuteCommand(const ASessionId: string; const CommandId: string; const ACommand: string): TCommandExecutionResult;
begin
  if Assigned(FShellService) then
    Result := FShellService.ExecuteCommand(ASessionId, CommandId, ACommand)
  else
    raise Exception.Create('Shell service not available');
end;

function TShellServiceAdapter.GetSession(const ASessionId: string): TSessionInfo;
begin
  if Assigned(FShellService) then
    Result := FShellService.GetSession(ASessionId)
  else
    raise Exception.Create('Shell service not available');
end;

function TShellServiceAdapter.GetAllSessions: TArray<TSessionInfo>;
begin
  if Assigned(FShellService) then
    Result := FShellService.GetAllSessions
  else
    SetLength(Result, 0);
end;

procedure TShellServiceAdapter.CloseSession(const ASessionId: string);
begin
  if Assigned(FShellService) then
    FShellService.CloseSession(ASessionId);
end;

procedure TShellServiceAdapter.CloseAllSessions;
begin
  if Assigned(FShellService) then
    FShellService.CloseAllSessions;
end;

function TShellServiceAdapter.GetShellServiceStats: TJSONObject;
begin
  if Assigned(FShellService) then
    Result := FShellService.GetServiceStats
  else
    Result := TJSONObject.Create;
end;

procedure TShellServiceAdapter.HandleValidationFailure(const ASessionId, ACommandId, ACommand, AErrorMessage: string; const AStartTime: TDateTime);
begin
  if Assigned(FShellService) then
    FShellService.HandleValidationFailure(ASessionId, ACommandId, ACommand, AErrorMessage, AStartTime);
end;

procedure TShellServiceAdapter.HandleExecutionFailure(const ASessionId, ACommandId, ACommand, AErrorMessage: string; const AStartTime: TDateTime);
begin
  if Assigned(FShellService) then
    FShellService.HandleExecutionFailure(ASessionId, ACommandId, ACommand, AErrorMessage, AStartTime);
end;

end.
