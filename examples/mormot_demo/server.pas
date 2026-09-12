unit server;

interface

{$I mormot.defines.inc}

uses
  SysUtils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.datetime,
  mormot.core.rtti,
  mormot.orm.core,
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
  public
    constructor Create(aModel: TOrmModel; const aDBFileName: TFileName);
      reintroduce;
    function GetInvoiceData(out Items: TDtoInvoiceRowDynArray): integer;
  end;

implementation

{ TDemoServer }

constructor TDemoServer.Create(aModel: TOrmModel; const aDBFileName: TFileName);
begin
  inherited Create(aModel, aDBFileName);
  CreateMissingTables;
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
         'ORDER BY o.SaleDate ASC';
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

initialization
  {$ifndef HASEXTRECORDRTTI}
  Rtti.RegisterFromText(TypeInfo(TDtoInvoiceRow),
    'OrderID: longint; OrderNo: RawUtf8; Company: RawUtf8; ' +
    'SaleDate: TDateTime; ItemsTotal: currency');
  {$endif HASEXTRECORDRTTI}

end.
