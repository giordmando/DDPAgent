unit RMC.Store.CollectionHandlers;

interface

uses
  Grijjy.Data.Bson,
  System.JSON,
  RMC.DataInterface,
  AgentServiceI,
  System.Generics.Collections,
  System.SysUtils,
  RMC.Store.CollectionInterface,
  System.SyncObjs,
  Shell.Interfaces;

type

  TCollectionHandlerFactory = class(TInterfacedObject, ICollectionHandlerFactory)

  private
    FApplicationFactories: TDictionary<string, IApplicationCollectionFactory>;
    FLock: TCriticalSection;

  protected
    // ICollectionHandlerFactory implementation
    function CreateHandlers(const AgentId: string; const AgentData: IAgentData;
     const OnDataChanged: TProc): TArray<ICollectionHandler>;

    // Registration methods
    procedure RegisterApplicationFactory(const AFactory: IApplicationCollectionFactory);
    procedure UnregisterApplicationFactory(const AApplicationName: string);
    function GetRegisteredApplications: TArray<string>;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  function GetCollectionHandlerFactory:ICollectionHandlerFactory;

implementation
  var
  _CollectionHandlerFactory:ICollectionHandlerFactory;

constructor TCollectionHandlerFactory.Create;
begin
  inherited;
  FApplicationFactories := TDictionary<string, IApplicationCollectionFactory>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TCollectionHandlerFactory.Destroy;
begin
  FLock.Free;
  FApplicationFactories.Free;
  inherited;
end;

function TCollectionHandlerFactory.CreateHandlers(const AgentId: string;
  const AgentData: IAgentData;
  const OnDataChanged: TProc): TArray<ICollectionHandler>;
var
  AllHandlers: TList<ICollectionHandler>;
  AppFactory: IApplicationCollectionFactory;
  AppHandlers: TArray<ICollectionHandler>;
  Handler: ICollectionHandler;
  i: Integer;
begin
  FLock.Enter;
  try
    AllHandlers := TList<ICollectionHandler>.Create;
    try
      // AUTOMATIC: Aggregate handlers from all registered application factories
      for AppFactory in FApplicationFactories.Values do
      begin
        WriteLn(Format('[Core] Creating collection handlers for application: %s', [AppFactory.GetApplicationName]));

        AppHandlers := AppFactory.CreateHandlers(AgentId, AgentData, OnDataChanged);
          for Handler in AppHandlers do
            AllHandlers.Add(Handler);
      end;

      // Convert to array
      SetLength(Result, AllHandlers.Count);
      for i := 0 to AllHandlers.Count - 1 do
        Result[i] := AllHandlers[i];

      WriteLn(Format('[Core] Created %d total collection handlers from %d applications',
        [Length(Result), FApplicationFactories.Count]));

    finally
      AllHandlers.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TCollectionHandlerFactory.RegisterApplicationFactory(const AFactory: IApplicationCollectionFactory);
begin
  FLock.Enter;
  try
    FApplicationFactories.AddOrSetValue(AFactory.GetApplicationName, AFactory);
    WriteLn(Format('[Core] Registered collection factory for application: %s', [AFactory.GetApplicationName]));
  finally
    FLock.Leave;
  end;
end;

procedure TCollectionHandlerFactory.UnregisterApplicationFactory(const AApplicationName: string);
begin
  FLock.Enter;
  try
    if FApplicationFactories.ContainsKey(AApplicationName) then
    begin
      FApplicationFactories.Remove(AApplicationName);
      WriteLn(Format('[Core] Unregistered collection factory for application: %s', [AApplicationName]));
    end;
  finally
    FLock.Leave;
  end;
end;

function TCollectionHandlerFactory.GetRegisteredApplications: TArray<string>;
begin
  FLock.Enter;
  try
    Result := FApplicationFactories.Keys.ToArray;
  finally
    FLock.Leave;
  end;
end;

function GetCollectionHandlerFactory: ICollectionHandlerFactory;
begin
  if not Assigned(_CollectionHandlerFactory) then
    _CollectionHandlerFactory := TCollectionHandlerFactory.Create;
  Result := _CollectionHandlerFactory;
end;

end.
