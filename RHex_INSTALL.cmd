@echo off
REM script for execution of  RichGSL.pl.
TITLE RHex_MakeExeZipWin
REM Running RHex_MakeExeZipWin.cmd

SETLOCAL
set exe_name=%0
REM ECHO "This exe_name is %exe_name%"
set script_name=%~n0
REM ECHO "This me is %script_name%"
set exe_dir=%~dp0
REM ECHO "This parent is %exe_dir%"
REM ECHO "------------------------------------------"

cd "%exe_dir%"
echo "In shell, current directory is %exe_dir% "
echo "Installing RHexSwing3D, RHexCast3D and RHexReplot3D."
echo

REM These link names must be as shown, since pp internalized them from the .pl's
REM mklink /H RHexSwing3D rhexexe 
REM mklink /H RHexCast3D rhexexe 
REM mklink /H RHexReplot3D rhexexe 
mklink RHexSwing3D rhexexe 
mklink RHexCast3D rhexexe 
mklink RHexReplot3D rhexexe 

echo "Done."
exit 0