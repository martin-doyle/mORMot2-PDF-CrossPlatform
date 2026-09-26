program peekpdf2;
uses SysUtils, StrUtils, Classes;
var
  data: AnsiString;
  raw: AnsiString;
  pos2, start, nl, e, idx: integer;
  b0: byte;
  f: TMemoryStream;
begin
  if ParamCount < 1 then
  begin
    writeln('usage: peekpdf2 <file.pdf>');
    halt(1);
  end;
  f := TMemoryStream.Create;
  f.LoadFromFile(ParamStr(1));
  SetLength(data, f.Size);
  Move(f.Memory^, data[1], f.Size);
  f.Free;
  idx := 0;
  pos2 := 1;
  while pos2 < Length(data) do
  begin
    start := strutils.PosEx('stream', data, pos2);
    if start = 0 then break;
    nl := strutils.PosEx(#10, data, start) + 1;
    e := strutils.PosEx('endstream', data, nl);
    if e = 0 then break;
    SetLength(raw, e - nl);
    if Length(raw) > 0 then
      Move(data[nl], raw[1], e - nl);
    if (Length(raw) > 0) then
    begin
      b0 := byte(raw[1]);
      if b0 <> $78 then
      begin
        if (Pos('rg'#10, raw) > 0) or (Pos(' m'#10, raw) > 0) then
        begin
          writeln('=== stream ', idx, ' len=', Length(raw), ' ===');
          writeln(Copy(raw, 1, 3000));
          writeln;
        end;
      end;
    end;
    pos2 := e + 9;
    inc(idx);
  end;
end.
