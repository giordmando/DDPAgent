unit RMC.DataInterface;

interface

uses
  Grijjy.Data.Bson,
  System.Generics.Collections,
  DDP.Interfaces,
  AgentServiceI;

type

  TCallMethodProc = reference to procedure(const AMethodName: string; const AParams: TgrBsonArray);
  TMethodDataHandlerProc = reference to function(const AMethod: string; const Params: TgrBsonDocument): TgrBsonArray;

  ISubscriptionCollection = interface
    procedure Subscribe(const ADDPClient: IDDPClient);
    function GetSubscriptionName: string;
    procedure SetSubscriptionName(const SubscriptionName: string);
    property SubscriptionName: string
      read GetSubscriptionName write SetSubscriptionName;
  end;

  IMethodDataHandler = interface
    function GetMethodName: string;
    function CanHandle(const AActionType: string): Boolean;
    function GetHandles: TDictionary<string, TMethodDataHandlerProc>;
    function HandleMethod(const AMethodType: string; const ADoc: TgrBsonDocument): TgrBsonArray;
  end;

  ISubscriptionRegistry = interface
    procedure RegisterCollection(const Collection: ISubscriptionCollection);
    procedure SubscribeAll(const ADDPClient:IDDPClient);
  end;

  IMethodDispatcher = interface
    procedure RegisterHandler(const AHandler: IMethodDataHandler);
    procedure UnregisterHandler(const AMethodName: string);
    procedure DispatchMethod(const AMethodName: string; const ADoc: TgrBsonDocument);
  end;

    //Application method factory interface
  IApplicationMethodFactory = interface
    function CreateHandlers(const AgentId: string; const AgentData: IAgentData;
     const CallMethodProc: TCallMethodProc): TArray<IMethodDataHandler>;
    function GetApplicationName: string;
  end;

  IMethodHandlerFactory = interface
    function CreateHandlers(const AgentId: string; const AgentData: IAgentData;
    const CallMethodProc: TCallMethodProc): TArray<IMethodDataHandler>;

    //Registration methods
    procedure RegisterApplicationFactory(const AFactory: IApplicationMethodFactory);
    procedure UnregisterApplicationFactory(const AApplicationName: string);
    function GetRegisteredApplications: TArray<string>;
  end;

implementation

end.

