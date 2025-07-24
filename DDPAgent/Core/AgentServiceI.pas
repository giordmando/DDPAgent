unit AgentServiceI;

interface
uses
  System.SysUtils,
  System.Threading,
  Grijjy.Data.Bson,
  System.Generics.Collections;

type

  // Interfaccia crittografia
  ICryptoProvider = interface
    function Encrypt(const Data: TBytes): TBytes;
    function Decrypt(const Data: TBytes): TBytes;
  end;

  // Interfaccia logging
  ILogger = interface
    procedure Info(const Msg: string);
    procedure Warn(const Msg: string);
    procedure Error(const Msg: string);
    procedure Debug(const Msg: string);
    function GetLogs: TArray<string>;
  end;

  // Interfaccia informazioni ambiente
  IEnvironmentInfo = interface
    function GetHomeDir: string;
    function GetInstallPath: string;
    function GetConfigDir: string;
    function GetTempDir: string;
    function GetHostname: string;
    function GetOSVersion: string;
    function IsWindows: Boolean;
    function IsLinux: Boolean;
  end;

  TMethodResult = record
    MethodName: string;
    Success: Boolean;
    Result: string;
    Error: string;
  end;

  IAgentData = interface

    function GetToken: string;
    procedure SetToken(const AValue: string);
    procedure SetAgentId(const AgentId: string);

    procedure SubscribeToCollections;

    function TestInsertSessionForAgent(const AAgentId: string; const FDDPSessionId: string): string;
    function TestInsertCommandForAgent(const AAgentId, ASessionId, ACommand: string): string;

    function GetResultQueue: TThreadedQueue<TMethodResult>;
    property ResultQueue: TThreadedQueue<TMethodResult> read GetResultQueue;
    procedure OnMethod(const AMethod: string; const ADoc: TgrBsonDocument);
  end;

implementation

end.
