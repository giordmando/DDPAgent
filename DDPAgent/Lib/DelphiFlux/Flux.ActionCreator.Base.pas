unit Flux.ActionCreator.Base;

interface

uses
  Flux.Dispatcher,
  System.SysUtils;

type
  TActionCreatorBase = class(TInterfacedObject)
  protected
    FDispatcher: IFluxDispatcher;
    procedure DoInBackground(const AJob: TProc);
    procedure InitializeFluxDependencies; virtual;
  public
    constructor Create;
  end;

implementation

uses
  System.Classes;

{ TActionCreatorBase }

constructor TActionCreatorBase.Create;
begin
  inherited Create;
  InitializeFluxDependencies;
end;

procedure TActionCreatorBase.DoInBackground(const AJob: TProc);
begin
  TThread.CreateAnonymousThread(
    procedure
    begin
      { TODO -oAC -cGeneral : Handle thread exception? Is it better to use TThreadPool? }
      try
        AJob();
      except
      end;
    end).Start;
end;

procedure TActionCreatorBase.InitializeFluxDependencies;
begin
  FDispatcher := GetFluxDispatcher();
end;

end.
