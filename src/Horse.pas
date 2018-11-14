unit Horse;

interface

uses
  System.SysUtils, System.Generics.Collections, System.Types,
  IPPeerServer, IPPeerAPI, IdHTTPServer, Web.HTTPApp, Horse.HTTP,
  Horse.Router, IdContext, IdCustomHTTPServer;

type
  EHorseCallbackInterrupted = Horse.HTTP.EHorseCallbackInterrupted;

  TProc = System.SysUtils.TProc;

  THorseList = Horse.HTTP.THorseList;

  THorseRequest = Horse.HTTP.THorseRequest;

  THorseHackRequest = Horse.HTTP.THorseHackRequest;

  THorseResponse = Horse.HTTP.THorseResponse;

  THorseHackResponse = Horse.HTTP.THorseHackResponse;

  THorseCallback = Horse.Router.THorseCallback;

  THorse = class
  private
    FPort: Integer;
    FRoutes: THorseRouterTree;
    FHTTPServer: TIdHTTPServer;

    procedure OnAuthentication(AContext: TIdContext; const AAuthType, AAuthData: String;
      var VUsername, VPassword: String; var VHandled: Boolean);
    procedure Initialize;
    procedure RegisterRoute(AHTTPType: TMethodType; APath: string; ACallback: THorseCallback);
    class var FInstance: THorse;
    procedure IdHTTPServerHandler(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo;
      AResponseInfo: TIdHTTPResponseInfo);
  public
    destructor Destroy; override;
    constructor Create(APort: Integer); overload;
    constructor Create; overload;
    property Port: Integer read FPort write FPort;
    property Routes: THorseRouterTree read FRoutes write FRoutes;
    procedure Use(APath: string; ACallback: THorseCallback); overload;
    procedure Use(ACallback: THorseCallback); overload;
    procedure Use(APath: string; ACallbacks: array of THorseCallback); overload;
    procedure Use(ACallbacks: array of THorseCallback); overload;

    procedure Get(APath: string; ACallback: THorseCallback); overload;
    procedure Get(APath: string; ACallbacks: array of THorseCallback); overload;
    procedure Put(APath: string; ACallback: THorseCallback); overload;
    procedure Put(APath: string; ACallbacks: array of THorseCallback); overload;
    procedure Post(APath: string; ACallback: THorseCallback); overload;
    procedure Post(APath: string; ACallbacks: array of THorseCallback); overload;
    procedure Delete(APath: string; ACallback: THorseCallback); overload;
    procedure Delete(APath: string; ACallbacks: array of THorseCallback); overload;

    procedure Start;
    procedure Stop;
    class function GetInstance: THorse;
  end;

implementation

uses Horse.Constants, System.IOUtils, IdSchedulerOfThreadPool;

constructor THorse.Create(APort: Integer);
begin
  FPort := APort;
  Initialize;
end;

constructor THorse.Create;
begin
  FPort := DEFAULT_PORT;
  Initialize;
end;

destructor THorse.Destroy;
begin
  FRoutes.free;
  FHTTPServer.Free;
  inherited;
end;

procedure THorse.Delete(APath: string; ACallbacks: array of THorseCallback);
var
  LCallback: THorseCallback;
begin
  for LCallback in ACallbacks do
  begin
    Delete(APath, LCallback);
  end;
end;

procedure THorse.Delete(APath: string; ACallback: THorseCallback);
begin
  RegisterRoute(mtDelete, APath, ACallback);
end;

procedure THorse.Initialize;
begin
  FInstance := Self;
  FRoutes := THorseRouterTree.Create;

  FHTTPServer := TIdHTTPServer.Create(nil);

  FHTTPServer.OnCommandGet := IdHTTPServerHandler;
  FHTTPServer.OnCommandOther := IdHTTPServerHandler;
  FHTTPServer.OnParseAuthentication := OnAuthentication;
  FHTTPServer.DefaultPort := FPort;
end;

procedure THorse.Get(APath: string; ACallback: THorseCallback);
begin
  RegisterRoute(mtGet, APath, ACallback);
end;

procedure THorse.Get(APath: string; ACallbacks: array of THorseCallback);
var
  LCallback: THorseCallback;
begin
  for LCallback in ACallbacks do
  begin
    Get(APath, LCallback);
  end;
end;

class function THorse.GetInstance: THorse;
begin
  Result := FInstance;
end;

procedure THorse.OnAuthentication(AContext: TIdContext; const AAuthType, AAuthData: String;
  var VUsername, VPassword: String; var VHandled: Boolean);
begin
  VHandled := True;
end;

procedure THorse.Post(APath: string; ACallback: THorseCallback);
begin
  RegisterRoute(mtPost, APath, ACallback);
end;

procedure THorse.Put(APath: string; ACallback: THorseCallback);
begin
  RegisterRoute(mtPut, APath, ACallback);
end;

procedure THorse.RegisterRoute(AHTTPType: TMethodType; APath: string; ACallback: THorseCallback);
begin
  if APath.EndsWith('/') then
    APath := APath.Remove(High(APath) - 1, 1);

  if not APath.StartsWith('/') then
    APath := '/' + APath;

  FRoutes.RegisterRoute(AHTTPType, APath, ACallback);
end;

procedure THorse.IdHTTPServerHandler(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo);
var
  LRequest: THorseRequest;
  LResponse: THorseResponse;
begin
  LRequest := THorseRequest.Create(ARequestInfo);
  LResponse := THorseResponse.Create(AResponseInfo);
  try
    AResponseInfo.ContentText := 'Not Found';
    AResponseInfo.ResponseNo := 404;
    try
      Routes.Execute(LRequest, LResponse);
    except
      on E: Exception do
        if not E.InheritsFrom(EHorseCallbackInterrupted) then
          raise;
    end;
  finally
    LRequest.Free;
    LResponse.Free;
  end;
end;

procedure THorse.Start;
var
  LAttach: string;
begin
  try
    FHTTPServer.Active := True;
    FHTTPServer.StartListening;
    if IsConsole then
    begin
      Writeln(Format(START_RUNNING, [FPort]));
      Write('Press return to stop ...');
      Read(LAttach);
      Stop;
    end;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end;

procedure THorse.Stop;
begin
  FHTTPServer.StopListening;
  FHTTPServer.Active := False;
  FHTTPServer.Bindings.Clear;
end;

procedure THorse.Use(ACallbacks: array of THorseCallback);
var
  LCallback: THorseCallback;
begin
  for LCallback in ACallbacks do
    Use(LCallback);
end;

procedure THorse.Use(APath: string; ACallbacks: array of THorseCallback);
var
  LCallback: THorseCallback;
begin
  for LCallback in ACallbacks do
    Use(APath, LCallback);
end;

procedure THorse.Use(ACallback: THorseCallback);
begin
  FRoutes.RegisterMiddleware('/', ACallback);
end;

procedure THorse.Use(APath: string; ACallback: THorseCallback);
begin
  FRoutes.RegisterMiddleware(APath, ACallback);
end;

procedure THorse.Post(APath: string; ACallbacks: array of THorseCallback);
var
  LCallback: THorseCallback;
begin
  for LCallback in ACallbacks do
    Post(APath, LCallback);
end;

procedure THorse.Put(APath: string; ACallbacks: array of THorseCallback);
var
  LCallback: THorseCallback;
begin
  for LCallback in ACallbacks do
    Put(APath, LCallback);
end;

end.
