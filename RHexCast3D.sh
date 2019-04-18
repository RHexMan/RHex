#!/usr/bin/env bash

# script for execution of  RHexCast3D.pl.
exe_name=$0
exe_dir=`dirname $0`
cd $exe_dir
echo "exe_dir=" $exe_dir
echo "------------------------------------------"
echo

# If there is an argument to this script, use it as the arg
# to the perl script.

if [[ $# > 0 ]]; then
    perl "RHexCast3D.pl" "$1"
else
    perl "RHexCast3D.pl"
fi
exit