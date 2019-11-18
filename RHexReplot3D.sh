#!/usr/bin/env bash
# script for execution of  RHexReplot3D.pl.

exe_name=$0
exe_dir=`dirname $0`
cd $exe_dir
#echo "In shell, current directory is " $exe_dir
#echo "------------------------------------------"
#echo

# If there is an argument to this script, use it as the arg
# to the perl script.
call_name=$exe_dir"/RHexReplot3D.pl"
#echo $call_name


if [[ $# > 0 ]]; then
    perl "$call_name" "$1"
else
    perl "$call_name"
fi
exit_status=$?

if [ $exit_status -ne 0 ]
then
	echo "Call failed, exit_status = $exit_status"
#	printf 'Call failed, exit code = %d\n' $exit_status
	echo
	echo "Press any key to close this window"
	read -n 1 -s
	# The -n 1 tells read to only read one character (rather than waiting for an ENTER keypress before returning), and -s tells it to be silent (so the key pressed is not echoed on the terminal).
fi

exit 0
