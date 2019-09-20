#!/usr/bin/env bash

# RHex_MakeExeZip
VERSION="-1.0.0"

exe_name=$0
exe_dir=`dirname $0`
cd $exe_dir
echo "exe_dir=" $exe_dir
echo "------------------------------------------"
echo

folder_name="RHex_Exe_Mac$VERSION"

rm -rf $folder_name

mkdir $folder_name

# As advertised, the -p option makes an zip a.par (2.6 MB).  So use The Unarchiver to open into a standard directory tree, 8.9 MB.  What you get is a stripped perl library tree, which hold just what was needed to satisfy all my dependencies, including RichGSL.pm and auto/RichGSL which contains what it always does, in particular, RichGSL.bundle (674 KB), which includes the required part of the GSL library as well as my RichGSL.o and rc_ode_solver.o.  Look at MANIFEST to see what all is there. IT DOES NOT APPEAR TO INCLUDE THE PERL INTERPRETER.

# If you run pp -o rhexexe a.par, it builds the standalone executable (about 7.5 MB).



#TEST-TEST - added -l and the executable pkg got bigger.  Does this mean I can use PerlGSL??? and just add in the dynamic libraries...

#From pp documentation:
#Note that even if your perl was built with a shared library, the 'Stand-alone executable' above will not need a separate perl5x.dll or libperl.so to function correctly. But even in this case, the underlying system libraries such as libc must be compatible between the host and target machines. Use --dependent if you are willing to ship the shared library with the application, which can significantly reduce the executable size.

#Note too:
#-u, --unicode

#    Package Unicode support (essentially utf8_heavy.pl and everything below the directory unicore in your perl library).

#pp -o rhexexe -c RHexSwing3D.pl RHexCast3D.pl RHexReplot3D.pl -l /Users/richmiller/perl5/perlbrew/perls/perl-5.28.1/lib/site_perl/5.28.1/auto/share/dist/Alien-GSL/lib/libgsl.dylib

#pp -p -c RHexSwing3D.pl RHexCast3D.pl RHexReplot3D.pl
pp -o rhexexe -c RHexSwing3D.pl RHexCast3D.pl RHexReplot3D.pl

mv rhexexe $folder_name

cp gnuplot gnuplot_x11 $folder_name


cp RHex_INSTALL.sh $folder_name

cp -R SpecFiles_Rod SpecFiles_Leader SpecFiles_Line SpecFiles_Preference SpecFiles_SwingDriver SpecFiles_CastDriver $folder_name

cp _RUN_TESTPLOT.txt $folder_name

cp LICENSE.md README.md README_EXE_INSTALL.md Documents/ParameterList_Swing.md $folder_name

#mv RHex_Exe "RHex_Exe$VERSION"

# When I try the next line, the files are all archived correctly, but the permissions (at least of the .sh) are lost.  The web commentary notes this and says use tar instead.  Currently, I zip manually, using Compress from the File menu.
#zip -r "RHex_Exe$VERSION.zip" "RHex_Exe$VERSION"

exit
