@echo off

TITLE RichGSL_MAKE
REM Running RichGSL_TEST.cmd

SETLOCAL
SET exe_name=%0
REM ECHO "This exe_name is %exe_name%"
SET script_name=%~n0
REM ECHO "This me is %script_name%"
SET exe_dir=%~dp0
REM ECHO "This parent is %exe_dir%"
REM ECHO "------------------------------------------"

CD "%exe_dir%"
ECHO "In shell, current directory is %exe_dir% "

call perl "RichGSL_TEST.pl"

@echo off
exit /B 0


