unit Shell.MethodHandlers;

interface

uses
  RMC.DataInterface, System.SysUtils, Grijjy.Data.Bson,
  System.Generics.Collections;

type
  TShellMethodHandler = class(TInterfacedObject, IMethodDataHandler)
  private
    FAgentId: string;
    FCallMethod: TCallMethodProc;
    FHandles: TDictionary<string, TMethodDataHandlerProc>;

    // Method implementations
    function RegisterAgent(const AMethod: string; const Doc: TgrBsonDocument): TgrBsonArray;
    function HandleTestPing(const AMethod: string; const Params: TgrBsonDocument): TgrBsonArray;
    function HandleSessionClose(const AMethod: string; const Params: TgrBsonDocument): TgrBsonArray;
    function HandleSessionStatus(const AMethod: string; const Params: TgrBsonDocument): TgrBsonArray;
    function HandleCommandExecution(const AMethod: string; const Params: TgrBsonDocument): TgrBsonArray;
    function HandleCommandOutput(const AMethod: string; const Params: TgrBsonDocument): TgrBsonArray;
    function HandleCommandComplete(const AMethod: string; const Params: TgrBsonDocument): TgrBsonArray;
    function HandleCommandError(const AMethod: string; const Params: TgrBsonDocument): TgrBsonArray;
    function HandleSessionHeartbeat(const AMethod: string; const Params: TgrBsonDocument): TgrBsonArray;
  public
    // IMethodDataHandler implementation
    function GetMethodName: string;
    function CanHandle(const AMethodName: string): Boolean;
    function HandleMethod(const AMethod: string; const ADoc: TgrBsonDocument): TgrBsonArray;
    function GetHandles: TDictionary<string, TMethodDataHandlerProc>;
  public
    constructor Create(const AgentId: string; const CallMethodProc: TCallMethodProc);
    destructor Destroy; override;
  end;

implementation

uses
  RMC.Actions.Consts;

constructor TShellMethodHandler.Create(const AgentId: string; const CallMethodProc: TCallMethodProc);
begin
  inherited Create;
  FAgentId := AgentId;
  FCallMethod := CallMethodProc;
  FHandles := TDictionary<string, TMethodDataHandlerProc>.Create;

  // Register shell methods from RMC.Actions.Consts.pas
  FHandles.Add(TEST_PING, HandleTestPing);
  FHandles.Add(SESSION_CLOSE, HandleSessionClose);
  FHandles.Add(SESSION_CLOSE_ALL, HandleSessionClose);
  FHandles.Add(SESSION_HEARTBEAT, HandleSessionHeartbeat);
  FHandles.Add(SESSION_STATUS, HandleSessionStatus);
  FHandles.Add(COMMAND_EXECUTION, HandleCommandExecution);
  FHandles.Add(COMMAND_OUTPUT, HandleCommandOutput);
  FHandles.Add(COMMAND_COMPLETED, HandleCommandComplete);
  FHandles.Add(COMMAND_SEND_ERROR, HandleCommandError);

  // Agent registration methods
  FHandles.Add(AGENT_REGISTER, RegisterAgent); // Reuse ping handler for simplicity
end;

destructor TShellMethodHandler.Destroy;
begin
  FHandles.Free;
  inherited;
end;

function TShellMethodHandler.GetHandles: TDictionary<string, TMethodDataHandlerProc>;
begin
  Result := FHandles;
end;

function TShellMethodHandler.GetMethodName: string;
begin
  Result := 'shell'; // Namespace
end;

function TShellMethodHandler.CanHandle(const AMethodName: string): Boolean;
begin
  Result := FHandles.ContainsKey(AMethodName);
end;

function TShellMethodHandler.HandleMethod(const AMethod: string; const ADoc: TgrBsonDocument): TgrBsonArray;
var
  Handler: TMethodDataHandlerProc;
begin
  WriteLn(Format('[Shell] Handling method: %s', [AMethod]));

  if FHandles.TryGetValue(AMethod, Handler) then
    Result := Handler(AMethod, ADoc)
  else
  begin
    WriteLn(Format('[Shell] Unknown method: %s', [AMethod]));
    Result := TgrBsonArray.Create;
  end;
end;

function TShellMethodHandler.RegisterAgent(const AMethod: string; const Doc: TgrBsonDocument): TgrBsonArray;
begin
  try
    if not Doc.Contains('session_id') then
      raise Exception.Create('Campo obbligatorio "session_id" mancante.');
    if not Doc.Contains('machine_id') then
      raise Exception.Create('Campo obbligatorio "machine_id" mancante.');

    // 4. Restituisci un array BSON col documento aggiornato
    Result := TgrBsonArray.Create([Doc]);
    if Assigned(FCallMethod) then
        FCallMethod(AMethod, Result);
    WriteLn('[Data] Agent registered: ' + FAgentId);

    except
      on E: Exception do
        WriteLn('[Data] Error registering agent: ' + E.Message);
    end;
end;

// Method implementations
function TShellMethodHandler.HandleTestPing(const AMethod: string; const Params: TgrBsonDocument): TgrBsonArray;
begin

  try
    if not Params.Contains('machine_id') then
      raise Exception.Create('Campo obbligatorio "machine_id" mancante.');

    Result := TgrBsonArray.Create([Params]);
    if Assigned(FCallMethod) then
      FCallMethod(AMethod, TgrBsonArray.Create([Params]));
  except
      on E: Exception do
        WriteLn('[Data] Error ping agent: ' + E.Message);
    end;
end;

function TShellMethodHandler.HandleSessionClose(const AMethod: string; const Params: TgrBsonDocument): TgrBsonArray;
var
  SessionId: string;
begin
  WriteLn(Format('[Shell] Handling %s', [AMethod]));

  if AMethod = SESSION_CLOSE_ALL then
  begin
    // Close all sessions for this agent
    FCallMethod(SESSION_CLOSE_ALL, TgrBsonArray.Create([
      Params
    ]));
  end
  else if AMethod = SESSION_CLOSE then
  begin
     if not Params.Contains('session_id') then
      raise Exception.Create('Campo obbligatorio "session_id" mancante.');
    if not Params.Contains('machine_id') then
      raise Exception.Create('Campo obbligatorio "machine_id" mancante.');

      FCallMethod(SESSION_CLOSE, TgrBsonArray.Create([
        Params
      ]));

  end;

  Result := TgrBsonArray.Create([
    TgrBsonDocument.Create.Add('success', True)
  ]);
end;

function TShellMethodHandler.HandleSessionStatus(const AMethod: string; const Params: TgrBsonDocument): TgrBsonArray;
var
  SessionId: string;
begin

  try
    if Assigned(FCallMethod) then
      FCallMethod(AMethod, TgrBsonArray.Create([Params]));
  except
      on E: Exception do
        WriteLn('[Data] Error ping agent: ' + E.Message);
    end;

  Result := TgrBsonArray.Create([
    TgrBsonDocument.Create.Add('success', True)
  ]);
end;

function TShellMethodHandler.HandleSessionHeartbeat(const AMethod: string; const Params: TgrBsonDocument): TgrBsonArray;

begin

  try
    if Assigned(FCallMethod) then
      FCallMethod(AMethod, TgrBsonArray.Create([Params]));

  except
      on E: Exception do
        WriteLn('[Data] Error ping agent: ' + E.Message);
  end;

  Result := TgrBsonArray.Create([
    TgrBsonDocument.Create.Add('success', True)
  ]);
end;

function TShellMethodHandler.HandleCommandExecution(const AMethod: string; const Params: TgrBsonDocument): TgrBsonArray;
begin
  WriteLn('[Shell] Handling command execution');

  if not Params.Contains('command_id') then
      raise Exception.Create('Campo obbligatorio "command_id" mancante.');

  if Assigned(FCallMethod) then
      FCallMethod(AMethod, TgrBsonArray.Create([Params]));

  Result := TgrBsonArray.Create([Params]);
end;

function TShellMethodHandler.HandleCommandOutput(const AMethod: string; const Params: TgrBsonDocument): TgrBsonArray;

begin
  WriteLn('[Shell] Handling command output');
  try
    if not Params.Contains('session_id') then
      raise Exception.Create('Campo obbligatorio "session_id" mancante.');
    if not Params.Contains('machine_id') then
      raise Exception.Create('Campo obbligatorio "machine_id" mancante.');
    if not Params.Contains('command_id') then
      raise Exception.Create('Campo obbligatorio "command_id" mancante.');

    Result := TgrBsonArray.Create([
      Params
    ]);
    if Assigned(FCallMethod) then
        FCallMethod(AMethod, Result);

    except
      on E: Exception do
        WriteLn('[Data] Error TCommandMethodHandler.SendOutput: ' + E.Message);
    end;
end;

function TShellMethodHandler.HandleCommandComplete(const AMethod: string; const Params: TgrBsonDocument): TgrBsonArray;
var
  CommandId: string;
  ExitCode: Integer;
begin
  WriteLn('[Shell] Handling command completion');

  try
    if not Params.Contains('exit_code') then
      raise Exception.Create('Campo obbligatorio "exit_code" mancante.');
    if not Params.Contains('machine_id') then
      raise Exception.Create('Campo obbligatorio "machine_id" mancante.');
    if not Params.Contains('command_id') then
      raise Exception.Create('Campo obbligatorio "command_id" mancante.');

    Result := TgrBsonArray.Create([
      TgrBsonDocument.Create.Add('success', True)
    ]);

    if Assigned(FCallMethod) then
        FCallMethod(AMethod, Result);

  except
      on E: Exception do
        WriteLn('[Data] TCommandMethodHandler.SendCommandComplete: ' + E.Message);
    end;


end;

function TShellMethodHandler.HandleCommandError(const AMethod: string; const Params: TgrBsonDocument): TgrBsonArray;
var
  CommandId, ErrorMessage: string;
begin
  try
    if not Params.Contains('session_id') then
      raise Exception.Create('Campo obbligatorio "session_id" mancante.');
    if not Params.Contains('machine_id') then
      raise Exception.Create('Campo obbligatorio "machine_id" mancante.');
    if not Params.Contains('error') then
      raise Exception.Create('Campo obbligatorio "error" mancante.');

    Result := TgrBsonArray.Create([
      TgrBsonDocument.Create.Add('success', True)
    ]);

    if Assigned(FCallMethod) then
        FCallMethod(AMethod, Result);

  except
      on E: Exception do
        WriteLn('[Data] Error TCommandMethodHandler.SendError: ' + E.Message);
    end;


end;

end.
