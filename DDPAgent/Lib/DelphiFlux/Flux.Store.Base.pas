unit Flux.Store.Base;

interface

uses
  Flux.Actions,
  Flux.Dispatcher,
  Grijjy.System.Messaging;

type
  TStoreBase = class(TInterfacedObject)
  protected
    FDispatcher: IFluxDispatcher;
    procedure InitializeFluxDependencies; virtual;
    procedure EmitStoreChange; virtual; abstract;
    procedure OnAction(const ASender: TObject; const AAction: TgrMessage);
      virtual; abstract;
  public
    constructor Create;
    destructor Destroy; override;
  end;

implementation

{ TStoreBase }

constructor TStoreBase.Create;
begin
  inherited;
  InitializeFluxDependencies;
  FDispatcher.&Register(TFluxAction, OnAction);
end;

destructor TStoreBase.Destroy;
begin
  FDispatcher.UnRegister(TFluxAction, OnAction);
  inherited;
end;

procedure TStoreBase.InitializeFluxDependencies;
begin
  FDispatcher := GetFluxDispatcher();
end;

end.
