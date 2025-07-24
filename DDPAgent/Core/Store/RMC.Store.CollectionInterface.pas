unit RMC.Store.CollectionInterface;

interface

uses
  Grijjy.Data.Bson,
  AgentServiceI,
  System.SysUtils,
  Shell.Interfaces;

  type
    // Interfaccia base per tutti gli handler di collection
  ICollectionHandler = interface
    function GetCollectionName: string;
    function CanHandle(const AActionType: string): Boolean;
    procedure HandleAction(const AActionType: string; const ADoc: TgrBsonDocument);
  end;

  //Application collection factory interface
  IApplicationCollectionFactory = interface
    ['{12345678-1234-1234-1234-123456789101}']
    function CreateHandlers(const AgentId: string; const AgentData: IAgentData;
       const OnDataChanged: TProc): TArray<ICollectionHandler>;
    function GetApplicationName: string;
  end;

  // Enhanced collection handler factory interface
  ICollectionHandlerFactory = interface
    ['{12345678-1234-1234-1234-123456789066}']
    function CreateHandlers(const AgentId: string; const AgentData: IAgentData;
     const OnDataChanged: TProc): TArray<ICollectionHandler>;

    //Registration methods
    procedure RegisterApplicationFactory(const AFactory: IApplicationCollectionFactory);
    procedure UnregisterApplicationFactory(const AApplicationName: string);
    function GetRegisteredApplications: TArray<string>;
  end;

implementation

end.
