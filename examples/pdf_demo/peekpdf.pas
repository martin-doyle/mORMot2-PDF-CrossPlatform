program peekpdf;
{$mode delphi}
uses SysUtils, Classes, ZStream;
var
  f: TFileStream;
  ms: TMemoryStream;
  ds: TDecompressionStream;
  buf: array[0..65535] of byte;
  n: integer;
  all: TMemoryStream;
  data, s: AnsiString;
  pos, start, nl, e, idx, streampos: integer;
  raw: AnsiString;
  b0: byte;
begin
  f := TFileStream.Create('output_crossplat.pdf', fmOpenRead);
  all := TMemoryStream.Create;
  all.CopyFrom(f, 0);
  f.Free;
  SetLength(data, all.Size);
  Move(all.Memory^, data[1], all.Size);
  idx := 0;
  pos := 1;
  while pos < Length(data) do
  begin
    start := PosEx('stream', data, pos);
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
    pos := e + 9;
    inc(idx);
  end;
  all.Free;
end.
