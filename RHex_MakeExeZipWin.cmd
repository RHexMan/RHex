@echo off
REM script for execution of  RichGSL.pl.
TITLE RHex_MakeExeZipWin
REM Running RHex_MakeExeZipWin.cmd
SETLOCAL

set VERSION=-0.1.0
set /A separate_executables=1	REM 1 or 0

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

IF /I "%separate_executables%" EQU "1" (
	echo Making separate executables...
	call pp -o RHexSwing3D.exe -c RHexSwing3D.pl
	call pp -o RHexCast3D.exe -c RHexCast3D.pl
	call pp -o RHexReplot3D.exe -c RHexReplot3D.pl
	move RHexSwing3D.exe %folder_name%
	move RHexCast3D.exe %folder_name%
	move RHexReplot3D.exe %folder_name%
) else (
	echo Making combined executable...
	call pp -o rhexexe -c RHexSwing3D.pl RHexCast3D.pl RHexReplot3D.pl
	move rhexexe %folder_name%
	xcopy README_EXE_INSTALL.md %folder_name%
	xcopy RHex_INSTALL.cmd %folder_name%
)

REM Robocopy doesn't seem to copy a list of directories
REM robocopy %exe_dir%\SpecFiles_Rod %exe_dir%\SpecFiles_Leader %folder_name%

xcopy  /E /I  SpecFiles_Rod %folder_name%\SpecFiles_Rod
xcopy  /E /I  SpecFiles_Leader %folder_name%\SpecFiles_Leader
xcopy  /E /I  SpecFiles_Line %folder_name%\SpecFiles_Line
xcopy  /E /I  SpecFiles_Preference %folder_name%\SpecFiles_Preference
xcopy  /E /I  SpecFiles_SwingDriver %folder_name%\SpecFiles_SwingDriver
xcopy  /E /I  SpecFiles_CastDriver %folder_name%\SpecFiles_CastDriver

robocopy .\  %folder_name%  _RUN_TESTPLOT.txt LICENSE.md README.md
xcopy Documents\ParameterList_Swing.md %folder_name%

REM When I try the next line, the files are all archived correctly, but the permissions (at least of the .sh) are lost.  The web commentary notes this and says use tar instead.  Currently, I zip manually, using Compress from the File menu.
REM zip -r "RHex_Exe$VERSION.zip" "RHex_Exe$VERSION"
exit /B 0
