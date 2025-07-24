unit RMC.Data;

interface

uses
  DDP.Interfaces,
  System.JSON,
  System.SysUtils,
  System.Generics.Collections,
  RMC.DataInterface,
  RMC.DataImpl,
  Grijjy.Data.Bson,
  RMC.Actions.Consts,
  System.Threading,
  RMCAgent.Config,
  AgentServiceI;

//type



function GetAgentData(const ADDPClient: IDDPClient): IAgentData;

implementation

uses

  System.SyncObjs,
  System.DateUtils,
  Nanosystems.Http,
  Nanosystems.Http.Factory,
  System.Classes;

var
  _Lock: TCriticalSection;
  _AgentData: IAgentData;

type
  TAgentData = class(TInterfacedObject, IAgentData)
  private
    FDDPClient: IDDPClient;
    FLock: TCriticalSection;
    FToken: string;
    FRestUrl: string;
    FAgentId:string;
    FResultQueue:TThreadedQueue<TMethodResult>;

    FRegistry: ISubscriptionRegistry;

    FMethodDispatcher:IMethodDispatcher;
    FMethodHandlerFactory:IMethodHandlerFactory;
    FMethodHandlers: TArray<IMethodDataHandler>;

    procedure CallMethod(const AMethodName: string; const AParams: TgrBsonArray);
    procedure DDPMethod(const AMethodName: string; const AParams: TgrBsonArray);
    procedure OnMethod(const AMethod: string; const ADoc: TgrBsonDocument);
  protected
    { IAgentData implementation }

    function GetToken: string;
    procedure SetToken(const AValue: string);
    procedure SetAgentId(const AgentId: string);

    procedure SubscribeToCollections;

    function TestInsertSessionForAgent(const AAgentId: string; const FDDPSessionId: string): string;
    function TestInsertCommandForAgent(const AAgentId, ASessionId, ACommand: string): string;

  public

    constructor Create(const ADDPClient: IDDPClient);
    destructor Destroy; override;
    function GetResultQueue: TThreadedQueue<TMethodResult>;
    property ResultQueue: TThreadedQueue<TMethodResult> read GetResultQueue;

  end;

{ TAgentData }

constructor TAgentData.Create(const ADDPClient: IDDPClient);
var
  H: IMethodDataHandler;
begin
  Assert(Assigned(ADDPClient));
  inherited Create;
  FDDPClient := ADDPClient;
  FLock := TCriticalSection.Create;
  FResultQueue := TThreadedQueue<TMethodResult>.Create;

  FAgentId := TAgentConfig.Instance.AgentId;

  FMethodDispatcher := TMethodDispatcher.Create; // VIOLAZIONE SOLID
  FMethodHandlerFactory := GetMethodHandlerFactory;

   // crea tutti gli handler in un colpo solo
  FMethodHandlers := FMethodHandlerFactory.CreateHandlers(FAgentId, Self, CallMethod);

  // registrali automaticamente
  for H in FMethodHandlers do
    FMethodDispatcher.RegisterHandler(H);

end;

destructor TAgentData.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TAgentData.GetResultQueue: TThreadedQueue<TMethodResult>;
begin
  Result := FResultQueue;
end;

function TAgentData.TestInsertSessionForAgent(const AAgentId: string; const FDDPSessionId: string): string;
begin
  try
    WriteLn('[AgentData] Calling test.insertSessionForAgent...');
    CallMethod('test.insertSessionForAgent',
      TgrBsonArray.Create([
        TgrBsonDocument.Create
        .Add('machine_id', AAgentId)
        .Add('ddpsession_id', FDDPSessionId)
      ]));

    WriteLn('[AgentData] Session inserted: ' + Result);
  except
    on E: Exception do
    begin
      WriteLn('[AgentData] Error in TestInsertSessionForAgent: ' + E.Message);
      Result := '';
    end;
  end;
end;

function TAgentData.TestInsertCommandForAgent(const AAgentId, ASessionId, ACommand: string): string;

begin
  try
    CallMethod('test.insertCommandForAgent',
      TgrBsonArray.Create([
        TgrBsonDocument.Create
          .Add('machine_id', AAgentId)
          .Add('session_id', ASessionId)
          .Add('command', ACommand)
      ]));
    WriteLn('[AgentData] Command inserted: ' + Result);
  except
    on E: Exception do
    begin
      WriteLn('[AgentData] Error in TestInsertCommandForAgent: ' + E.Message);
      Result := '';
    end;
  end;
end;

procedure TAgentData.CallMethod(const AMethodName: string; const AParams: TgrBsonArray);
begin
    DDPMethod(AMethodName, AParams);
end;

procedure TAgentData.DDPMethod(const AMethodName: string; const AParams: TgrBsonArray);
begin
  try
    TThread.CreateAnonymousThread(
      procedure
      var
      MethodResult: TMethodResult;
      begin
        try
          var Result := FDDPClient.Method(AMethodName, AParams);

          WriteLn(Format('[Data] Method %s result: %s',
            [AMethodName, Result.ToJson]));
          MethodResult.Success := True;
          MethodResult.Result := Result.ToJson;
        except
          on E: Exception do
            WriteLn(Format('[Data] DDP method %s failed: %s', [AMethodName, E.Message]));
        end;
        ResultQueue.PushItem(MethodResult);
      end
      ).Start;

    WriteLn(Format('[Data] DDP method %s called asynchronously', [AMethodName]));
  except
    on E: Exception do
      WriteLn(Format('[Data] Error calling DDP method %s: %s', [AMethodName, E.Message]));
  end;
end;

function TAgentData.GetToken: string;
begin
  FLock.Enter;
  try
    Result := FToken;
  finally
    FLock.Leave;
  end;
end;

procedure TAgentData.SetToken(const AValue: string);
begin
  FLock.Enter;
  try
    FToken := AValue;
  finally
    FLock.Leave;
  end;
end;
procedure TAgentData.SetAgentId(const AgentId: string);
begin
  FAgentId := AgentId;
end;

// ========================================================================
// SOTTOSCRIZIONI DDP
// ========================================================================

procedure TAgentData.SubscribeToCollections;
  var
  LSubscriptionRegistry :ISubscriptionRegistry;
begin
  LSubscriptionRegistry := GetSubscriptionRegistry;
  LSubscriptionRegistry.SubscribeAll(FDDPClient);
end;

// ========================================================================
// METHODS DDP
// ========================================================================

procedure TAgentData.OnMethod(const AMethod: string; const ADoc: TgrBsonDocument);
var
  LDoc: TgrBsonDocument;
begin
  WriteLn('[DEBUG TStoreAgent] OnAction chiamato');
  if Assigned(FMethodDispatcher) then
    FMethodDispatcher.DispatchMethod(AMethod, ADoc);
end;

// ========================================================================
// FACTORY FUNCTION
// ========================================================================


function GetAgentData(const ADDPClient: IDDPClient): IAgentData;
begin
  if not Assigned(_AgentData) then
  begin
    _Lock.Enter;
    try
      _AgentData := TAgentData.Create(ADDPClient);
      WriteLn('[DEBUG] AgentData created and registered');

    finally
      _Lock.Leave;
    end;
    Result := TAgentData.Create(ADDPClient);
  end;
end;

initialization

_Lock := TCriticalSection.Create;

finalization

_Lock.Free;

end.
