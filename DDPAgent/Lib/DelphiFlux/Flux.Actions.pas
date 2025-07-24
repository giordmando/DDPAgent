unit Flux.Actions;

interface

uses
  Grijjy.Data.Bson,
  Grijjy.System.Messaging;

type
  TFluxAction = class(TgrMessage)
  private
    FType: string;
    FData: TgrBsonDocument;
  public
    constructor Create(const AType: string); overload;
    constructor Create(const AType: string;
      const AData: TgrBsonDocument); overload;
    property &Type: string read FType;
    property Data: TgrBsonDocument read FData;
  end;

implementation

{ TFluxAction }

constructor TFluxAction.Create(const AType: string);
begin
  inherited Create;
  FType := AType;
end;

constructor TFluxAction.Create(const AType: string;
  const AData: TgrBsonDocument);
begin
  inherited Create;
  FType := AType;
  FData := AData;
end;

end.
