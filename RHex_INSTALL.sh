#!/usr/bin/env bash

# script for installation of the RHex executables.
exe_name=$0
exe_dir=`dirname $0`
cd $exe_dir
echo "In shell, current directory is " $exe_dir "."
echo "Installing RHexSwing3D and RHexReplot3D."
echo

ln rhexexe RHexSwing3D
ln rhexexe RHexReplot3D

echo "Done."
