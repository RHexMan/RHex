#!/usr/bin/env bash

# RHex_MakeExeZip
VERSION="-0.1.0"

exe_name=$0
exe_dir=`dirname $0`
cd $exe_dir
echo "exe_dir=" $exe_dir
echo "------------------------------------------"
echo

rm -rf "RHex_Exe$VERSION"

mkdir RHex_Exe

pp -o rhexexe -c RHexSwing3D.pl RHexCast3D.pl RHexReplot3D.pl

mv rhexexe RHex_Exe/

cp gnuplot gnuplot_x11 RHex_Exe/


cp RHex_INSTALL.sh RHex_Exe/

cp -R SpecFiles_Rod SpecFiles_Leader SpecFiles_Line SpecFiles_Preference SpecFiles_SwingDriver SpecFiles_CastDriver RHex_Exe/

cp _RUN_TESTPLOT.txt RHex_Exe/

cp LICENSE.md README.md README_EXE_INSTALL.md Documents/ParameterList_Swing.md RHex_Exe/

mv RHex_Exe "RHex_Exe$VERSION"

# When I try the next line, the files are all archived correctly, but the permissions (at least of the .sh) are lost.  The web commentary notes this and says use tar instead.  Currently, I zip manually, using Compress from the File menu.
#zip -r "RHex_Exe$VERSION.zip" "RHex_Exe$VERSION"

exit
