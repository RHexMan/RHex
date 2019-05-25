@echo off
TITLE RHexReplot3D
REM Running RHexReplot3D.cmd

SETLOCAL
SET exe_name=%0
REM ECHO "This exe_name is %exe_name%"
SET script_name=%~n0
REM ECHO "This me is %script_name%"
SET exe_dir=%~dp0
REM ECHO "This parent is %exe_dir%"
REM ECHO "------------------------------------------"

CD "%exe_dir%"
REM ECHO "In shell, current directory is %exe_dir% "echo

SET call_name="%exe_dir%RHexReplot3D.pl"

REM If there is an argument to this script, use it as the arg
REM # to the perl script.

REM if [[ $# > 0 ]]; then
REM     perl "%call_name%" "%1"
REM else
call perl "%call_name%"
REM fi
exit 0
