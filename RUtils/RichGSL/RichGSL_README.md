### RichGSL_README - Instructions for building `RichGSL` and, in particular, `RichGSL::rc_ode_solve`

`RichGSL::rc_ode_solve` is self-contained perl extension (XS) code that gives perl access to the GSL (Gnu Scientific Library) ode solver.  It is self-contained in that the required part of the GSL library is copied into the XS bundle at compile time.

This was done to make the RHex executables as independent of dynamic libraries as possible, and thus more available to user who are not computer savvy. If the distributed code is is incompatible with your machine, you will need to rebuild RichGSL.  The instructions are below.  You will need to have the static libraries `libgsl` and `libgslcblas` available.  They can be downloaded from http://reflection.oss.ou.edu/gnu/gsl/.

There is a standard perl module `PerlGSL::DiffEq` available from CPAN that came earlier and does much the same thing, except that it's XS code dynamically links to the GSL libraries.

### The easy build

In the original distribution, the folder `RStaticLib` contains libraries `libgsl.a`, `libgsl.la`, `libgslcblas.a`, and `libgslcblas.la` that run on the more recent Mac operating systems (eg, El Capitan).  If you think your system is compatible, simply run the shell script `RichGSL_MAKE.sh` from where it stands in the folder that contains this README.  If the build works, you're done.  `RichGSL` is installed in your perl library.

if the build doesn't work, you will need to download copies of these libraries built for your machine.  Go to the link mentioned above.  Replace the libraries in `RStaticLib` with the newly downloaded ones.  Run `RichGSL_MAKE.sh` again.


### Build from scratch

The perl distribution comes with binaries that to some extent automate the creation of XS modules.  Of particular interest here is the executable `h2xs`, which under perlbrew, is located in the bin folder directly under your perl version.

As in the easy build, download library files `libgsl.a`, `libgsl.la`, `libgslcblas.a`, and `libgslcblas.la` suited to your machine.

Then, suppose you want to work in a directory `MY_XS`. Create a folder in `MY_XS` named `RStaticLib`, and copy the downloaded library files into it. Then copy all the files in `RichGSL_Source` into `RHex_XS`.  

In Terminal, `cd` to `MY_XS`, run

`h2xs -Afn RichGSL`

This makes a new folder `RichGSL`, with an elaborate set of subfolders, in `RHex_XS`. Among other things, it writes the file `RichGSL.pm` and puts it in the `lib` subfolder. The `RichGSL.pm` code is fine, but we want to install our pod documentation, so replace the created file by the one from source.

`cp RichGSL.pm RichGSL/lib/RichGSL.pm`

The next step should have been trivial, but due to an "incorrectable bug" in `h2xs`, you need to do something more elaborate. Run

```
cp rc_ode_solver_kluge.h RichGSL/rc_ode_solver.h
cp rc_ode_solver.c RichGSL/
```

and

`h2xs -Oxan RichGSL rc_ode_solver.h -L../RStaticLib -lgsl -lgslcblas`

This last generates `RichGSL.xs` making its best guess based on `rc_ode_solver.h`. It also adds the static libraries and some constant(?) manipulation code to Makefile.PL.

Here is the kluge.  In order to get past the bug mentioned above, the .h file needed to have no #include of other .h files, and also could not have variables of the perl type AV* (pointer to perl array). In the file `rc_ode_solver_kluge.h` copied and renamed above, the AV*'s were replaced by void*'s, which `h2xs -Oxan` could handle, and the #includes were removed.  But if we simply continued from here, we would not get the right glue code.  So, at this point, overwrite the `.xs` with the one from source, and replace `RichGSL/rc_ode_solver.h` by the one really need.

```
cp rc_ode_solver_final.h RichGSL/rc_ode_solver.h
cp RichGSL.xs RichGSL/RichGSL.xs
```

Now we're ready to go.

```
cd RichGSL
perl Makefile.PL
make perl
make test_static
make install
```
