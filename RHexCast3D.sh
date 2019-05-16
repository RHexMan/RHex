#!/usr/bin/env bash
# script for execution of  RHexCast3D.pl.

exe_name=$0
exe_dir=`dirname $0`
cd $exe_dir

# If there is an argument to this script, use it as the arg
# to the perl script.
call_name=$exe_dir"/RHexCast3D.pl"
#echo $call_name

if [[ $# > 0 ]]; then
    perl "$call_name" "$1"
else
    perl "$call_name"
fi
exit
