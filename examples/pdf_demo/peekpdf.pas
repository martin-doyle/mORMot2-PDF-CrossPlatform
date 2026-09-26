program peekpdf;
{$mode delphi}
uses SysUtils, StrUtils, Classes, ZStream;
var
  f: TFileStream;
  ms: TMemoryStream;
  ds: TDecompressionStream;
  buf: array[0..65535] of byte;
  n: integer;
  all: TMemoryStream;
  data, s: AnsiString;
  p, start, nl, e, idx, streampos: integer;
  raw: AnsiString;
  b0: byte;
begin
  if ParamCount < 1 then
  begin
    writeln('usage: peekpdf <file.pdf>');
    halt(1);
  end;
  f := TFileStream.Create(ParamStr(1), fmOpenRead);
  all := TMemoryStream.Create;
  all.CopyFrom(f, 0);
  f.Free;
  SetLength(data, all.Size);
  Move(all.Memory^, data[1], all.Size);
  idx := 0;
  p := 1;
  while p < Length(data) do
  begin
    start := PosEx('stream', data, p);
    if start = 0 then break;
    nl := PosEx(#10, data, start) + 1;
    e := PosEx('endstream', data, nl);
    if e = 0 then break;
    SetLength(raw, e - nl);
    Move(data[nl], raw[1], e - nl);
    if Length(raw) > 0 then
    begin
      b0 := byte(raw[1]);
      if b0 <> $78 then  // not compressed
      begin
        if (Pos(' m'#10, raw) > 0) or (Pos(' l'#10, raw) > 0) or
           (Pos('BT'#10, raw) > 0) or (Pos('rg'#10, raw) > 0) then
        begin
          writeln('=== stream ', idx, ' len=', Length(raw), ' ===');
          writeln(Copy(raw, 1, 2000));
        end;
      end;
    end;
    p := e + 9;
    inc(idx);
  end;
  all.Free;
end.
