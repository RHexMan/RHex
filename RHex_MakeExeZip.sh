#!/usr/bin/env bash

# RHex_MakeExeZip

exe_name=$0
exe_dir=`dirname $0`
cd $exe_dir
echo "exe_dir=" $exe_dir
echo "------------------------------------------"
echo

mkdir RHex_Exe

pp -o rhexexe -c RHexSwing3D.pl RHexReplot3D.pl

mv rhexexe RHex_Exe

cp rgnuplot rgnuplotx RHex_Exe

cp RHex_INSTALL.sh RHex_Exe

cp -R SpecFiles_Leader SpecFiles_Line SpecFiles_Preference SpecFiles_SwingDriver RHex_Exe/

cp Documents/README.md Documents/ParameterList_Swing.md RHex_Exe

exit
