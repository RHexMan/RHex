### RichGSL_BUILD - Instructions for building `RichGSL` and, in particular, `RichGSL::rc_ode_solve`.

`RichGSL::rc_ode_solve` is self-contained perl extension (XS) code that gives perl access to the GSL (Gnu Scientific Library) ode solver.  It is self-contained in that the required part of the GSL library was copied into the XS bundle at compile time.

This was done to make the RHex executables as independent of dynamic libraries as possible, and thus more available to user who are not computer savvy. If the distributed code is is incompatible with your machine, you will need to rebuild RichGSL.  The instructions are below.  You will need to have the static libraries `libgsl` and `libgslcblas` available.  They can be downloaded from http://reflection.oss.ou.edu/gnu/gsl/.

There is a standard perl module `PerlGSL::DiffEq` available from CPAN that came earlier and does much the same thing, except that it's XS code dynamically links to the GSL libraries.

Suppose your working directory is `RHex_XS`.  Keep copies of the files rc_ode_solve.c, rc_ode_solve.h, and RichGSL.t, and `Makefile.PL` as well as a copy of the folder `RStaticLib` (which contains `libgsl.a`, `libgsl.la`, `libgslcblas.a`, and `libgslcblas.la`) there.  In terminal, `cd` into `RHex_XS`, then type
 
`h2xs -Afn RichGSL`

A new folder `RichGSL` will be created in `RHex_XS`.  Copy all the above named files into `RichGSL` and then `cd` into it.

OK to have return and y in .c be AV*, but not in .h (see below).
move .c,.h into RichGSL
h2xs -Oxan RichGSL rc_ode_solve.h -L/sw/lib -lgsl

Generates the .xs, making its best guess based on the .h.  Adds the libraries and some constant(?) manipulation code to Makefile.PL.

This is all truly weird.  If I put the perl include in, and run the above, I get lots of problems.  Someplace I saw a warning that  some xs necessary bug prohibits #includes in the .h.

If I take the includes out, and use AV* as the return in rc_ode_solver.h, of course, it fails.  I stumbled on making the return void*, double* y, no includes, and then using the above h2xs.  This makes a good .xs, except, of course, the return is void*, and y is double*.  Edit the file to change the return and y to AV*.

Continuing,
cd RichGSL
perl Makefile.PL
is ok.

If I then, go back and put #include "EXTERN.h" and
#include "perl.h" back in the rc_ode_solver.h, and replace the return void* by AV*, then

make perl

works! On success, renames RichGSL.xsc to RichGSL.c.

make test_static
make install
