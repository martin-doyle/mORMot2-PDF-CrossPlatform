@echo off
rem Build one project of this repository with the Delphi 2010 command line
rem compiler (roadmap R-25): the first Unicode Delphi check. Win32 only.
rem
rem   tests\build_delphi2010.bat <project.lpr|project.dpr> [extra dcc32 options]
rem
rem   MORMOT2     mORMot2 checkout (the folder holding src\), required
rem   DELPHI2010  Delphi 2010 root,
rem               default "C:\Program Files (x86)\Embarcadero\RAD Studio\7.0"
rem
rem Output: bin\d2010\<project>\ below the repository root. A .lpr is copied
rem to a .dpr there, because dcc32 wants one - the .lpr stays the only source.
rem
rem Warnings stay on, unlike build_delphi7.bat: the implicit string casts
rem (W1057/W1058) are what R-25 looks for.
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
if "%DELPHI2010%"=="" set "DELPHI2010=C:\Program Files (x86)\Embarcadero\RAD Studio\7.0"
if not exist "%DELPHI2010%\bin\dcc32.exe" (
  echo dcc32.exe not found below "%DELPHI2010%"
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
set "OUT=%ROOT%\bin\d2010\%PRJ%"
if not exist "%OUT%\dcu" mkdir "%OUT%\dcu"
copy /y "%~f1" "%OUT%\%PRJ%.dpr" >nul

set "M=%MORMOT2%\src"
set "UNITS=%PRJDIR%;%ROOT%\src\core;%ROOT%\src\pdf"
set "UNITS=%UNITS%;%M%\core;%M%\lib;%M%\crypt;%M%\net;%M%\db;%M%\orm;%M%\rest;%M%\soa;%M%\misc"
set "UNITS=%UNITS%;%DELPHI2010%\lib"
rem %M% for mormot.defines.inc, which every unit of ours includes by name (R-21)
rem %PRJDIR% for the project's own .inc files: the .dpr is compiled from %OUT%
set "INCS=%PRJDIR%;%M%"

pushd "%OUT%"
"%DELPHI2010%\bin\dcc32.exe" -B -Q -H- -U"%UNITS%" -I"%INCS%" -R"%DELPHI2010%\lib;%PRJDIR%" -N0dcu -E. %2 %3 %4 %5 %6 %7 %8 %9 "%PRJ%.dpr"
set "RC=%ERRORLEVEL%"
popd
exit /b %RC%
