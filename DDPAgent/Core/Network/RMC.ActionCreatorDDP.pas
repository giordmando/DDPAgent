unit RMC.ActionCreatorDDP;

interface

uses
  Grijjy.Data.Bson, DDP.Interfaces, RMC.Store.Agent, DDP.Actions.Consts,
  Flux.Actions, Flux.ActionCreator.Base;

type
  TRMCActionCreatorDDP = class(TActionCreatorBase, IActionCreatorDDP)
  private
   FAgentStore:IStoreAgent;
  protected
    { IActionCreatorDDP implementation }
    procedure Added(const AJsonDoc: TgrBsonDocument);
    procedure Changed(const AJsonDoc: TgrBsonDocument);
    procedure Removed(const AJsonDoc: TgrBsonDocument);
    procedure Ready(const AJsonDoc: TgrBsonDocument);
    procedure NoSub(const AJsonDoc: TgrBsonDocument);
  public
    constructor Create;
  end;

implementation

{ TRMCActionCreatorDDP }

constructor TRMCActionCreatorDDP.Create;
begin
  FAgentStore := GetStoreAgent;
end;

procedure TRMCActionCreatorDDP.Added(const AJsonDoc: TgrBsonDocument);
begin

  WriteLn('[DEBUG TActionCreatorDDP] Dispatch completed ********');
  WriteLn(AJsonDoc.ToJson);
  WriteLn('*******  ********');

  // *** TEST DIRETTO FUNZIONA!!!!!!***
  WriteLn('[DEBUG TActionCreatorDDP] Testing direct Store access...');

  if Assigned(FAgentStore) then
  begin
    WriteLn('[DEBUG TActionCreatorDDP] Calling Store.OnAction directly');
    FAgentStore.OnAction(nil, TFluxAction.Create(ACTION_DDP_DOCUMENT_ADDED, AJsonDoc));
  end;

end;

procedure TRMCActionCreatorDDP.Changed(const AJsonDoc: TgrBsonDocument);
begin
  if Assigned(FAgentStore) then
  begin
    WriteLn('[DEBUG TActionCreatorDDP] Calling Store.OnAction directly');
    FAgentStore.OnAction(nil, TFluxAction.Create(ACTION_DDP_DOCUMENT_CHANGED, AJsonDoc));
  end;
end;

procedure TRMCActionCreatorDDP.Removed(const AJsonDoc: TgrBsonDocument);
begin
  if Assigned(FAgentStore) then
  begin
    WriteLn('[DEBUG TActionCreatorDDP] Calling Store.OnAction directly');
    FAgentStore.OnAction(nil, TFluxAction.Create(ACTION_DDP_DOCUMENT_REMOVED, AJsonDoc));
  end;
end;

procedure TRMCActionCreatorDDP.Ready(const AJsonDoc: TgrBsonDocument);
begin
  FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_SUBSCRIBED, AJsonDoc));
end;

procedure TRMCActionCreatorDDP.NoSub(const AJsonDoc: TgrBsonDocument);
begin
  FDispatcher.DoDispatch(TFluxAction.Create(ACTION_DDP_UNSUBSCRIBED, AJsonDoc));
end;

end.
