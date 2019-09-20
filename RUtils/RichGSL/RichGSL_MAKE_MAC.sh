
#!/usr/bin/env bash

# This script builds RichGSL when executed in the parent folder of the RichGSL_TEMPLATE folder.  There must be a sibling folder of this script named RStaticLib that contains copies of the libraries  `libgsl.a`, `libgsl.la`, `libgslcblas.a`, and `libgslcblas.la`

exe_name=$0
exe_dir=`dirname $0`
cd $exe_dir
echo "exe_dir=" $exe_dir
echo "------------------------------------------"
echo

rm -rf RichGSL_WORKING
cp -r RichGSL_TEMPLATE RichGSL_WORKING
cd RichGSL_WORKING
echo "Working in "
pwd
perl Makefile.PL

# Note: The whole `make perl` thing is a red herring.  We don't want a stand-alone perl at this level.  That is done when all else is ready by PAR::Packer.  Here, just pointing to the static gsl libraries causes the ordinary make to include the code required from them to be put in RichGSL.bundle

make
make test
make install
# If I have previously removed .../site_perl/5.28.1/darwin-2level/RichGSL and ditto/auto/RichGSL, then Installing /Users/richmiller/perl5/perlbrew/perls/perl-5.28.1/lib/site_perl/5.28.1/darwin-2level/auto/RichGSL/extralibs.all extralibs.ld (which have the same content as before, so, remarkably, still pointing to the libs in RHex/RUtils/RichGSL/RStaticLib_MAC) autosplit.ix (which has nearly no content, but announces itself a timestamp) RichGSL.a (11KB, just what was in working) and RichGSL.bundle (674KB. This last is strange, since it seems to have been made silently by the install process if make test_static was never called.  That make created it explicitly).




