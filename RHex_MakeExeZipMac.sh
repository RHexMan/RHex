#!/usr/bin/env bash

# RHex_MakeExeZip
VERSION="-0.1.0"

exe_name=$0
exe_dir=`dirname $0`
cd $exe_dir
echo "exe_dir=" $exe_dir
echo "------------------------------------------"
echo

folder_name="RHex_Exe_Mac$VERSION"

rm -rf $folder_name

mkdir $folder_name

pp -o rhexexe -c RHexSwing3D.pl RHexCast3D.pl RHexReplot3D.pl

mv rhexexe $folder_name

cp gnuplot gnuplot_x11 $folder_name


cp RHex_INSTALL.sh $folder_name

cp -R SpecFiles_Rod SpecFiles_Leader SpecFiles_Line SpecFiles_Preference SpecFiles_SwingDriver SpecFiles_CastDriver $folder_name

cp _RUN_TESTPLOT.txt $folder_name

cp LICENSE.md README.md README_EXE_INSTALL.md Documents/ParameterList_Swing.md $folder_name

#mv RHex_Exe "RHex_Exe$VERSION"

# When I try the next line, the files are all archived correctly, but the permissions (at least of the .sh) are lost.  The web commentary notes this and says use tar instead.  Currently, I zip manually, using Compress from the File menu.
#zip -r "RHex_Exe$VERSION.zip" "RHex_Exe$VERSION"

exit
