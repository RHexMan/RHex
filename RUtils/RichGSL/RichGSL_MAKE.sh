#!/usr/bin/env bash

# script for execution of  RichGSL.pl.
exe_name=$0
exe_dir=`dirname $0`
cd $exe_dir
echo "exe_dir=" $exe_dir
echo "------------------------------------------"
echo

# This script builds RichGSL when executed in the parent folder of the RichGSL_TEMPLATE folder.  There must be a sibling folder of this script named RStaticLib that contains copies of the libraries  `libgsl.a`, `libgsl.la`, `libgslcblas.a`, and `libgslcblas.la`

rm -rf RichGSL_WORKING
cp -r RichGSL_TEMPLATE RichGSL_WORKING
cd RichGSL_WORKING
rm -f RichGSL.c RichGSL.o
perl Makefile.PL
make perl
# make static seems to do the same thing, but is depreciated.
make test_static
make install
