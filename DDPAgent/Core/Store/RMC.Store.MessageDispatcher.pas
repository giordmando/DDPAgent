unit RMC.Store.MessageDispatcher;

interface

uses
  RMC.Store.CollectionInterface,
  DDP.Actions.Consts,
  Grijjy.Data.Bson,
  System.Generics.Collections,
  System.SysUtils;

type
  IMessageDispatcher = interface
    procedure RegisterHandler(const AHandler: ICollectionHandler);
    procedure UnregisterHandler(const ACollectionName: string);
    procedure DispatchMessage(const AActionType: string; const ADoc: TgrBsonDocument);
  end;

  TMessageDispatcher = class(TInterfacedObject, IMessageDispatcher)
  private
    FHandlers: TDictionary<string, ICollectionHandler>;
  protected
    procedure RegisterHandler(const AHandler: ICollectionHandler);
    procedure UnregisterHandler(const ACollectionName: string);
    procedure DispatchMessage(const AActionType: string; const ADoc: TgrBsonDocument);
  public
    constructor Create;
    destructor Destroy; override;
  end;

implementation

constructor TMessageDispatcher.Create;
begin
  inherited;
  FHandlers := TDictionary<string, ICollectionHandler>.Create;
end;

destructor TMessageDispatcher.Destroy;
begin
  FHandlers.Free;
  inherited;
end;

procedure TMessageDispatcher.RegisterHandler(const AHandler: ICollectionHandler);
begin
  if Assigned(AHandler) then
    FHandlers.AddOrSetValue(AHandler.GetCollectionName, AHandler);
end;

procedure TMessageDispatcher.UnregisterHandler(const ACollectionName: string);
begin
  FHandlers.Remove(ACollectionName);
end;

procedure TMessageDispatcher.DispatchMessage(const AActionType: string; const ADoc: TgrBsonDocument);
var
  Collection: string;
  Handler: ICollectionHandler;
begin
  if not ADoc.Contains('collection') then
    Exit;

  Collection := ADoc['collection'].AsString;

  if FHandlers.TryGetValue(Collection, Handler) then
  begin
    if Handler.CanHandle(AActionType) then
      Handler.HandleAction(AActionType, ADoc);
  end
  else
    WriteLn(Format('[MessageDispatcher] No handler registered for collection: %s', [Collection]));
end;

end.
