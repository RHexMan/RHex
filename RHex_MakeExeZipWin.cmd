@echo off
REM script for execution of  RichGSL.pl.
TITLE RHex_MakeExeZipWin
REM Running RHex_MakeExeZipWin.cmd
SETLOCAL

set VERSION=-1.0.0

set exe_name=%0
REM ECHO "This exe_name is %exe_name%"
set script_name=%~n0
REM ECHO "This me is %script_name%"
set exe_dir=%~dp0
REM ECHO "This parent is %exe_dir%"
REM ECHO "------------------------------------------"

cd "%exe_dir%"
echo "In shell, current directory is %exe_dir% "

set folder_name=RHex_Exe_Win%VERSION%
rmdir /Q /S  %folder_name%
mkdir %folder_name%
echo Creating folder %folder_name%

REM call pp -p -c RHexSwing3D.pl
REM Strawberry perl has set the path to include C:\Strawberry\c\bin, which contains the dynamic libs.  Note that the specific names are not generic as for the .a's
REM call pp -r -o RHexSwing3D.exe -c RHexSwing3D.pl -l libgsl-19__.dll -l libgslcblas-0__.dll
REM call pp -o RHexSwing3D.exe -c RHexSwing3D.pl -l C:\Strawberry\c\bin\libgsl-19__.dll -l C:\Strawberry\c\bin\libgslcblas-0__.dll

REM call pp -o RHexSwing3D.exe -c RHexSwing3D.pl -l libgsl-19__.dll -l libgslcblas-0__.dll
REM move RHexSwing3D.exe %folder_name%
REM exit /B 0

echo Making combined executable...
call pp -o rhex.exe -c RHexSwing3D.pl RHexCast3D.pl RHexReplot3D.pl -l C:\Strawberry\c\bin\libgsl-19__.dll -l C:\Strawberry\c\bin\libgslcblas-0__.dll
move rhex.exe %folder_name%
REM xcopy README_EXE_INSTALL.md %folder_name%
xcopy RHex_INSTALL.cmd %folder_name%

REM Robocopy doesn't seem to copy a list of directories
REM robocopy %exe_dir%\SpecFiles_Rod %exe_dir%\SpecFiles_Leader %folder_name%

xcopy  /E /I  SpecFiles_Rod %folder_name%\SpecFiles_Rod
xcopy  /E /I  SpecFiles_Leader %folder_name%\SpecFiles_Leader
xcopy  /E /I  SpecFiles_Line %folder_name%\SpecFiles_Line
xcopy  /E /I  SpecFiles_Preference %folder_name%\SpecFiles_Preference
xcopy  /E /I  SpecFiles_SwingDriver %folder_name%\SpecFiles_SwingDriver
xcopy  /E /I  SpecFiles_CastDriver %folder_name%\SpecFiles_CastDriver

robocopy .\  %folder_name%  _RUN_TESTPLOT.txt LICENSE.md README.md README_EXE_INSTALL.md
xcopy Documents\ParameterList_Swing.md %folder_name%

REM Now zip up the resulting folder and you're done.

exit /B 0
