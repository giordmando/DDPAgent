unit RMCAgent.Config;

interface

uses
  System.SysUtils,
  System.IniFiles,
  System.IOUtils,
  System.SyncObjs;

type
  TAgentConfig = class
  strict private
    class var FInstance: TAgentConfig;
    class var FLock: TCriticalSection;
    class constructor Create;
    class destructor Destroy;

  private
    FSessionLimit: Integer;
    FShellType: string;
    FChannelType: string;
    FHttpURL: string;
    FHttpRetries: Integer;
    FHttpTimeout: Integer;
    FReconnectAttempts: Integer;
    FHeartbeatInterval: Integer;
    FLogFile: string;
    FAuthWhitelist: TArray<string>;
    FAuthBlacklist: TArray<string>;
    FConfigFile: string;
    FAgentId: string;
    FDppURL: string;
    FToken: string;

    constructor CreateInternal(const AConfigFile: string);
    procedure SetDefaults;
  public
    /// Ritorna l’unica istanza di TAgentConfig (creata al bisogno)
    class function Instance(const AConfigFile: string = 'agent.conf.ini'): TAgentConfig;
    //constructor Create(const AConfigFile: string = '');
    destructor Destroy; override;

    procedure LoadFromFile;
    procedure SaveToFile;

    // Properties
    property AgentId: string read FAgentId write FAgentId;
    property Token: string read FToken write FToken;
    property SessionLimit: Integer read FSessionLimit write FSessionLimit;
    property ShellType: string read FShellType write FShellType;
    property ChannelType: string read FChannelType write FChannelType;
    property HttpURL: string read FHttpURL write FHttpURL;
    property DppURL: string read FDppURL write FDppURL;
    property HttpRetries: Integer read FHttpRetries write FHttpRetries;
    property HttpTimeout: Integer read FHttpTimeout write FHttpTimeout;
    property ReconnectAttempts: Integer read FReconnectAttempts write FReconnectAttempts;
    property HeartbeatInterval: Integer read FHeartbeatInterval write FHeartbeatInterval;
    property LogFile: string read FLogFile write FLogFile;
    property AuthWhitelist: TArray<string> read FAuthWhitelist write FAuthWhitelist;
    property AuthBlacklist: TArray<string> read FAuthBlacklist write FAuthBlacklist;

  end;

implementation

{ TAgentConfig }

class constructor TAgentConfig.Create;
begin
  FLock := TCriticalSection.Create;
  FInstance := nil;
end;

class destructor TAgentConfig.Destroy;
begin
  // Distrugge l'istanza se ancora presente
  FLock.Enter;
  try
    FreeAndNil(FInstance);
  finally
    FLock.Leave;
    FLock.Free;
  end;
end;

constructor TAgentConfig.CreateInternal(const AConfigFile: string);
begin
  inherited Create;
  if AConfigFile <> '' then
    FConfigFile := AConfigFile
  else
    // Percorso di default: stesso .exe con estensione .ini
    FConfigFile := ChangeFileExt(ParamStr(0), '.ini');

  SetDefaults;
  if TFile.Exists(FConfigFile) then
    LoadFromFile;
end;

destructor TAgentConfig.Destroy;
begin
  inherited;
end;

procedure TAgentConfig.SetDefaults;
begin
  FAgentId := 'agent_12345678';
  FShellType := 'cmd';
  FSessionLimit := 10;
  FChannelType := 'ddp';
  FHttpURL := 'http://localhost:3000';
  FDppURL := 'ws://127.0.0.1:3000/websocket';
  //FDppURL := 'wss://console.supremocontrol.com/websocket';
  FHttpTimeout := 30000;
  FHttpRetries := 3;
  FReconnectAttempts := 5;
  FHeartbeatInterval := 30000;
  FLogFile := 'agent.log';
  FToken := 'ccc';
  FAuthWhitelist := ['dir*', 'cd*', 'echo*', 'ping*', 'ipconfig*', 'systeminfo'];
  FAuthBlacklist := ['format*', 'del /s*', 'rm -rf*', 'shutdown*', 'net user*'];
end;

class function TAgentConfig.Instance(const AConfigFile: string = 'agent.conf.ini'): TAgentConfig;
begin
  // Double-checked locking per thread-safety
  if FInstance = nil then
  begin
    FLock.Enter;
    try
      if FInstance = nil then
        FInstance := TAgentConfig.CreateInternal(AConfigFile);
    finally
      FLock.Leave;
    end;
  end;
  Result := FInstance;
end;

procedure TAgentConfig.LoadFromFile;
var
  LIni: TIniFile;
begin
  LIni := TIniFile.Create(FConfigFile);
  try
    FShellType := LIni.ReadString('Shell', 'ShellType', FShellType);
    FSessionLimit := LIni.ReadInteger('Session', 'SessionLimit', FSessionLimit);
    FChannelType := LIni.ReadString('Channel', 'ChannelType', FChannelType);

    FHttpURL := LIni.ReadString('HTTP', 'URL', FHttpURL);
    FHttpTimeout := LIni.ReadInteger('HTTP', 'Timeout', FHttpTimeout);
    FHttpRetries := LIni.ReadInteger('HTTP', 'Retries', FHttpRetries);

    FReconnectAttempts := LIni.ReadInteger('Reconnect', 'ReconnectAttempts', FReconnectAttempts);
    FHeartbeatInterval := LIni.ReadInteger('Reconnect', 'HeartbeatInterval', FHeartbeatInterval);
    FDppURL := LIni.ReadString('Connection', 'ServerURL', FDppURL);
    FLogFile := LIni.ReadString('Logging', 'File', FLogFile);

    FToken := LIni.ReadString('Auth', 'Token', FToken);

    FAuthWhitelist := LIni.ReadString('AuthRules', 'Whitelist', '').Split([',']);
    FAuthBlacklist := LIni.ReadString('AuthRules', 'Blacklist', '').Split([',']);
  finally
    LIni.Free;
  end;
end;

procedure TAgentConfig.SaveToFile;
var
  LIni: TIniFile;
begin
  LIni := TIniFile.Create(FConfigFile);
  try
    LIni.WriteString('Shell', 'ShellType', FShellType);
    LIni.WriteInteger('Session', 'SessionLimit', FSessionLimit);
    LIni.WriteString('Channel', 'ChannelType', FChannelType);

    LIni.WriteString('HTTP', 'URL', FHttpURL);
    LIni.WriteInteger('HTTP', 'Timeout', FHttpTimeout);
    LIni.WriteInteger('HTTP', 'Retries', FHttpRetries);

    LIni.WriteInteger('Reconnect', 'ReconnectAttempts', FReconnectAttempts);
    LIni.WriteInteger('Reconnect', 'HeartbeatInterval', FHeartbeatInterval);
    LIni.WriteString('Connection', 'ServerURL', FDppURL);
    LIni.WriteString('Logging', 'File', FLogFile);
    LIni.WriteString('Auth', 'Token', FToken);
    LIni.WriteString('AuthRules', 'Whitelist', string.Join(',', FAuthWhitelist));
    LIni.WriteString('AuthRules', 'Blacklist', string.Join(',', FAuthBlacklist));
  finally
    LIni.Free;
  end;
end;

end.
