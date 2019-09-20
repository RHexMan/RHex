@echo off

TITLE RichGSL_MAKE
REM Running RichGSL_MAKE_WIN.cmd

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


REM  This script builds RichGSL for WINDOWS when executed in the parent folder of the RichGSL_TEMPLATE folder.  Unlike the case for the MAC, the windows stand-alone executable uses the GSL dynamically (rather than statically) linked libraries.  Under the current version of Strawberry PERL, these are located in C:\Strawberry\c\bin and are named `libgsl-19__.dll` and `libgslcblas-0__.dll`.
@echo on
rmdir /Q /S  RichGSL_WORKING
xcopy /E /I RichGSL_TEMPLATE RichGSL_WORKING

REM Overwriting the template makefile.  The library specifications there end up pointing to the dynamic libraries.
xcopy /Y Makefile_WIN.PL RichGSL_WORKING\Makefile.PL

cd RichGSL_WORKING
dir

del /Q RichGSL.c RichGSL.o
perl Makefile.PL
dir
gmake
gmake test
gmake install

@echo off
exit /B 0


