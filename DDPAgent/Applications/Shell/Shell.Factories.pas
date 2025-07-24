unit Shell.Factories;

interface

uses
  RMC.DataInterface, RMC.Store.CollectionInterface,
  System.SysUtils, Shell.Interfaces,
  RMC.ShellServiceFactory, AgentServiceI;

type
 TShellMethodFactory = class(TInterfacedObject, IApplicationMethodFactory)
  private
    FShellServiceFactory: TShellServiceFactory;
  protected
    function CreateHandlers(const AgentId: string; const AgentData: IAgentData;
    const CallMethodProc: TCallMethodProc): TArray<IMethodDataHandler>;
    function GetApplicationName: string;
  public
    constructor Create(const AShellSesriceFactory: TShellServiceFactory);
  end;

  // Shell collection factory
  TShellCollectionFactory = class(TInterfacedObject, IApplicationCollectionFactory)
  private
    FShellServiceFactory: TShellServiceFactory;
  protected
    function CreateHandlers(const AgentId: string; const AgentData: IAgentData;
       const OnDataChanged: TProc): TArray<ICollectionHandler>;
    function GetApplicationName: string;
  public
    constructor Create(const AShellSesriceFactory: TShellServiceFactory);
  end;


// MANUAL registration functions - chiamare esplicitamente nel main program
procedure RegisterShellFactories(const AShellSesriceFactory: TShellServiceFactory);
procedure UnregisterShellFactories;

implementation

uses
  Shell.MethodHandlers, Shell.CollectionHandlers,
  RMC.DataImpl, RMC.Store.CollectionHandlers;

var
  _ShellMethodFactory: IApplicationMethodFactory;
  _ShellCollectionFactory: IApplicationCollectionFactory;


constructor TShellMethodFactory.Create(
  const AShellSesriceFactory: TShellServiceFactory);
begin
  inherited Create;
  FShellServiceFactory := AShellSesriceFactory;
end;

function TShellMethodFactory.CreateHandlers(const AgentId: string; const AgentData: IAgentData;
 const CallMethodProc: TCallMethodProc): TArray<IMethodDataHandler>;
var
    LShellSessionService: IShellSessionService;
begin
  WriteLn('[Shell] Creating shell method handlers');
  if not Assigned(FShellServiceFactory) then
    raise Exception.Create('[Shell] Service Factory (ShellServiceFactory) not inizialized.');
  LShellSessionService := FShellServiceFactory.CreateShellSessionService(AgentData);
  SetLength(Result, 1);
  Result[0] := TShellMethodHandler.Create(AgentId, CallMethodProc);

  WriteLn('[Shell] Created 1 method handler');
end;

function TShellMethodFactory.GetApplicationName: string;
begin
  Result := 'Shell';
end;

{ TShellCollectionFactory }


constructor TShellCollectionFactory.Create(
  const AShellSesriceFactory: TShellServiceFactory);
begin
  inherited Create;
  FShellServiceFactory := AShellSesriceFactory;
end;

function TShellCollectionFactory.CreateHandlers(const AgentId: string; const AgentData: IAgentData;
  const OnDataChanged: TProc): TArray<ICollectionHandler>;
  var
    LShellSessionService: IShellSessionService;
begin
  WriteLn('[Shell] Creating shell collection handlers');
  if not Assigned(FShellServiceFactory) then
    raise Exception.Create('[Shell] Service Factory (ShellServiceFactory) not inizialized.');
  LShellSessionService := FShellServiceFactory.CreateShellSessionService(AgentData);
  SetLength(Result, 2);
  Result[0] := TSessionHandler.Create(AgentId, AgentData, LShellSessionService, OnDataChanged);
  Result[1] := TCommandHandler.Create(AgentId, AgentData, LShellSessionService, OnDataChanged);

  WriteLn('[Shell] Created 2 collection handlers (sessions, commands)');
end;

function TShellCollectionFactory.GetApplicationName: string;
begin
  Result := 'Shell';
end;

// MANUAL registration functions
procedure RegisterShellFactories(const AShellSesriceFactory: TShellServiceFactory);
begin
  WriteLn('[Shell] MANUAL: Registering Shell application factories...');

  try
    _ShellMethodFactory := TShellMethodFactory.Create(AShellSesriceFactory);
    _ShellCollectionFactory := TShellCollectionFactory.Create(AShellSesriceFactory);

    var LMethodHandlerFactory := GetMethodHandlerFactory;
    // Register with core factories
    LMethodHandlerFactory.RegisterApplicationFactory(_ShellMethodFactory);
    GetCollectionHandlerFactory.RegisterApplicationFactory(_ShellCollectionFactory);

    WriteLn('[Shell] MANUAL: Shell application factories registered successfully');
  except
    on E: Exception do
    begin
      WriteLn('[Shell] ERROR during manual registration: ' + E.ClassName + ': ' + E.Message);
      raise;
    end;
  end;
end;

procedure UnregisterShellFactories;
var
  MethodFactory: IMethodHandlerFactory;
  CollectionFactory: ICollectionHandlerFactory;
begin
  WriteLn('[Shell] MANUAL: Unregistering Shell application factories...');
  MethodFactory := GetMethodHandlerFactory;
  CollectionFactory := GetCollectionHandlerFactory;

  try
    if Assigned(MethodFactory) then
      GetMethodHandlerFactory.UnregisterApplicationFactory('Shell');
    if Assigned(CollectionFactory) then
      GetCollectionHandlerFactory.UnregisterApplicationFactory('Shell');

    _ShellMethodFactory := nil;
    _ShellCollectionFactory := nil;

    WriteLn('[Shell] MANUAL: Shell application factories unregistered');
  except
    on E: Exception do
      WriteLn('[Shell] Error during manual unregistration: ' + E.Message);
  end;
end;

end.
