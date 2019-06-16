@echo off

TITLE RichGSL_MAKE
REM Running RichGSL_MAKE.cmd

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


REM  This script builds RichGSL when executed in the parent folder of the RichGSL_TEMPLATE folder.  There must be a sibling folder of this script named RStaticLib that contains copies of the libraries  `libgsl.a`, `libgsl.la`, `libgslcblas.a`, and `libgslcblas.la`
@echo on
rmdir /Q /S  RichGSL_WORKING
Xcopy /E /I RichGSL_TEMPLATE_WIN RichGSL_WORKING
REM Xcopy /E /I RichGSL_TEMPLATE_DYN_WIN RichGSL_WORKING
cd RichGSL_WORKING
dir
del /Q RichGSL.c RichGSL.o
REM perl Makefile.PL LINKTYPE=static DLEXT=a
REM perl Makefile.PL LINKTYPE=static
perl Makefile.PL
dir
gmake
gmake test
gmake install

@echo off
exit /B 0


