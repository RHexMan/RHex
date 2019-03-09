#!/usr/bin/env bash

exe_name=$0
exe_dir=`dirname $0`
echo "------------------------------------------"

#cd $exe_dir
cd "$exe_dir"
echo $exe_dir

perl -v
perl "LIST_INCLUDES.pl"

exit
