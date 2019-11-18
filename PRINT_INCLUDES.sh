#!/usr/bin/env bash
# script for execution of  PRINT_INCLUDES.pl.

exe_name=$0
exe_dir=`dirname $0`
cd $exe_dir

# If there is an argument to this script, use it as the arg
# to the perl script.
call_name=$exe_dir"/PRINT_INCLUDES.pl"
#echo $call_name

perl "$call_name"
sleep 1000
#pause -1 "Press any key"
exit
