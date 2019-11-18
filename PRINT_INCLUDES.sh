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

echo
echo "Press any key to close this window"
read -n 1 -s
	# The -n 1 tells read to only read one character (rather than waiting for an ENTER keypress before returning), and -s tells it to be silent (so the key pressed is not echoed on the terminal).
exit 0
