unit server;

interface

{$I mormot.defines.inc}

uses
  SysUtils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.datetime,
  mormot.core.rtti,
  mormot.orm.base,
  mormot.orm.core,
  mormot.db.raw.sqlite3,
  mormot.rest.sqlite3,
  mormot.db.raw.sqlite3.static,
  data;

type
  PDtoInvoiceRow = ^TDtoInvoiceRow;

  TDtoInvoiceRow = packed record
    OrderID: longint;
    OrderNo: RawUtf8;
    Company: RawUtf8;
    SaleDate: TDateTime;
    ItemsTotal: currency;
  end;

  TDtoInvoiceRowDynArray = array of TDtoInvoiceRow;

  { TDemoServer }

  TDemoServer = class(TRestServerDB)
  protected
    procedure AddSampleData;
  public
    // the virtual constructor: TRestClientDB creates its server through it
    constructor Create(aModel: TOrmModel; aDB: TSqlDataBase;
      aHandleUserAuthentication: boolean = false;
      aOwnDB: boolean = false); overload; override;
    function GetInvoiceData(out Items: TDtoInvoiceRowDynArray): integer;
  end;

/// the demo database: data/mormot_demo.db in the demo folder, two levels above
// the executable - or below the current folder, for a build that lands
// elsewhere (Delphi 7: bin/d7/mormot_demo, run from the demo folder)
function DemoDatabaseFile: TFileName;

/// opens the demo database and returns its invoice rows
function ReadInvoiceData(out Items: TDtoInvoiceRowDynArray): integer;

implementation

const
  // invented for this demo, so the data stays under the project's licence
  SAMPLE_CUSTOMERS: array[0..9] of RawUtf8 = (
    'Blue Lagoon Divers', 'Coral Reef Supplies', 'Deep Sea Outfitters',
    'Harbor Light Marine', 'Kelp Forest Trading', 'Manta Bay Sports',
    'North Shore Aquatics', 'Pearl Island Gear', 'Sandbar Expeditions',
    'Tidewater Equipment');
  // enough rows for a table across several pages
  SAMPLE_ORDERS = 200;

{ TDemoServer }

constructor TDemoServer.Create(aModel: TOrmModel; aDB: TSqlDataBase;
  aHandleUserAuthentication: boolean; aOwnDB: boolean);
begin
  inherited Create(aModel, aDB, aHandleUserAuthentication, aOwnDB);
  CreateMissingTables;
  // a fresh database gets the sample data; a downloaded one is kept as it is
  if (not Orm.TableHasRows(TOrmCustomer)) and
     (not Orm.TableHasRows(TOrmCustomerOrder)) then
    AddSampleData;
end;

// computed, not random: the demo PDF has to be the same on every run
procedure TDemoServer.AddSampleData;
var
  batch: TRestBatch;
  customer: TOrmCustomer;
  order: TOrmCustomerOrder;
  i, cents: integer;
  day: TDateTime;
begin
  batch := TRestBatch.Create(Orm, nil);
  customer := TOrmCustomer.Create;
  order := TOrmCustomerOrder.Create;
  try
    for i := 0 to high(SAMPLE_CUSTOMERS) do
    begin
      customer.IDValue := i + 1;
      customer.CustomerNo := 'C' + UInt3DigitsToUtf8(i + 1);
      customer.Company := SAMPLE_CUSTOMERS[i];
      batch.Add(customer, {SendData=}true, {ForceID=}true);
    end;
    for i := 0 to SAMPLE_ORDERS - 1 do
    begin
      day := EncodeDate(2026, 1, 1) + (i * 90) div SAMPLE_ORDERS; // Q1/2026
      order.OrderNo := 'ORD-2026-' + UInt4DigitsToUtf8(i + 1);
      order.SaleDate := TimeLogFromDateTime(day);
      order.ShipDate := TimeLogFromDateTime(day + 3);
      order.Customer := TOrmCustomer(PtrInt((i * 7 + i div 10) mod 10 + 1));
      cents := 5000 + (i * 7919) mod 495000;
      order.ItemsTotal := cents * 0.01;
      batch.Add(order, {SendData=}true);
    end;
    if Orm.BatchSend(batch) <> HTTP_SUCCESS then
      EOrmException.RaiseUtf8('%: the sample data was not stored', [self]);
  finally
    order.Free;
    customer.Free;
    batch.Free;
  end;
end;

function TDemoServer.GetInvoiceData(out Items: TDtoInvoiceRowDynArray): integer;
var
  SQL: RawUtf8;
  Table: TOrmTable;
  i: integer;
  SaleDateValue: Int64;
begin
  Items := nil;
  SQL := 'SELECT o.ID, o.OrderNo, c.Company, o.SaleDate, o.ItemsTotal ' +
         'FROM CustomerOrder o ' +
         'INNER JOIN Customer c ON o.Customer = c.ID ' +
         'ORDER BY o.SaleDate ASC, o.ID ASC';
  Table := Self.Orm.ExecuteList([TOrmCustomerOrder, TOrmCustomer], SQL);
  if Table <> nil then
  try
    SetLength(Items, Table.RowCount);
    for i := 1 to Table.RowCount do
    begin
      Items[i - 1].OrderID := Table.GetAsInteger(i, 0);
      Items[i - 1].OrderNo := Table.GetU(i, 1);
      Items[i - 1].Company := Table.GetU(i, 2);
      SaleDateValue := Table.GetAsInt64(i, 3);
      if SaleDateValue > 0 then
        Items[i - 1].SaleDate := TimeLogToDateTime(SaleDateValue)
      else
        Items[i - 1].SaleDate := 0;
      Items[i - 1].ItemsTotal := Table.GetAsCurrency(i, 4);
    end;
  finally
    Table.Free;
  end;
  Result := Length(Items);
end;

function DemoDatabaseFile: TFileName;
var
  dir: TFileName;
begin
  dir := Executable.ProgramFilePath + '..' + PathDelim + '..' + PathDelim + 'data';
  if not DirectoryExists(dir) then
    dir := 'data';
  // SQLite does not create the folder: without it the demo fails on open
  result := EnsureDirectoryExists(dir, EOSException) +
    Utf8ToString(Executable.ProgramName) + '.db';
end;

function ReadInvoiceData(out Items: TDtoInvoiceRowDynArray): integer;
var
  Model: TOrmModel;
  Client: TRestClientDB;
begin
  Model := CreateModel;
  try
    Client := TRestClientDB.Create(Model, nil, DemoDatabaseFile, TDemoServer,
      false, '');
    try
      result := TDemoServer(Client.Server).GetInvoiceData(Items);
    finally
      Client.Free;
    end;
  finally
    Model.Free;
  end;
end;

initialization
  {$ifndef HASEXTRECORDRTTI}
  Rtti.RegisterFromText(TypeInfo(TDtoInvoiceRow),
    'OrderID: longint; OrderNo: RawUtf8; Company: RawUtf8; ' +
    'SaleDate: TDateTime; ItemsTotal: currency');
  {$endif HASEXTRECORDRTTI}

end.
