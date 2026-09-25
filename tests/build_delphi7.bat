@echo off
rem Build one project of this repository with the Delphi 7 command line
rem compiler (roadmap R-19). Win32 only.
rem
rem   tests\build_delphi7.bat <project.lpr|project.dpr> [extra dcc32 options]
rem
rem   MORMOT2   mORMot2 checkout (the folder holding src\), required
rem   DELPHI7   Delphi 7 root, default "C:\Program Files (x86)\Borland\Delphi7"
rem
rem Output: bin\d7\<project>\ below the repository root. A .lpr is copied to a
rem .dpr there, because dcc32 wants one - the .lpr stays the only source.
rem
rem mORMot2\src\ui is deliberately NOT on the search path: it holds the original
rem mormot.ui.pdf, mormot.ui.report and mormot.ui.core, which the compiler would
rem take instead of ours without a word.
setlocal

if "%~1"=="" (
  echo usage: %~nx0 ^<project.lpr^|project.dpr^> [extra dcc32 options]
  exit /b 2
)
if "%MORMOT2%"=="" (
  echo MORMOT2 is not set - point it to the mORMot2 checkout
  exit /b 2
)
if "%DELPHI7%"=="" set "DELPHI7=C:\Program Files (x86)\Borland\Delphi7"
if not exist "%DELPHI7%\Bin\DCC32.EXE" (
  echo DCC32.EXE not found below "%DELPHI7%"
  exit /b 2
)
if not exist "%MORMOT2%\src\mormot.defines.inc" (
  echo mormot.defines.inc not found below "%MORMOT2%\src"
  exit /b 2
)

set "ROOT=%~dp0.."
rem no trailing backslash: before a closing quote it would escape the quote
set "PRJDIR=%~dp1"
set "PRJDIR=%PRJDIR:~0,-1%"
set "PRJ=%~n1"
set "OUT=%ROOT%\bin\d7\%PRJ%"
if not exist "%OUT%\dcu" mkdir "%OUT%\dcu"
copy /y "%~f1" "%OUT%\%PRJ%.dpr" >nul

set "M=%MORMOT2%\src"
set "UNITS=%PRJDIR%;%ROOT%\src\core;%ROOT%\src\platform\windows;%ROOT%\src\lib"
set "UNITS=%UNITS%;%M%\core;%M%\lib;%M%\crypt;%M%\net;%M%\db;%M%\orm;%M%\rest;%M%\soa;%M%\misc"
set "UNITS=%UNITS%;%DELPHI7%\Lib"
rem "..\mormot.defines.inc" is resolved against the include path by FPC and
rem against the unit's own folder by Delphi; %M%\core makes "..\" hit %M%
set "INCS=%M%;%M%\core;%ROOT%\src\core"

rem -N and -E are relative: dcc32 7 splits them at a space even when quoted
pushd "%OUT%"
"%DELPHI7%\Bin\DCC32.EXE" -B -Q -H- -W- -U"%UNITS%" -I"%INCS%" -R"%DELPHI7%\Lib;%PRJDIR%" -Ndcu -E. %2 %3 %4 %5 %6 %7 %8 %9 "%PRJ%.dpr"
set "RC=%ERRORLEVEL%"
popd
exit /b %RC%
