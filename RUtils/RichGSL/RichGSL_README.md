### RichGSL_README - Instructions for building `RichGSL` and, in particular, `RichGSL::rc_ode_solve`

For the MAC, `RichGSL::rc_ode_solve` is a self-contained perl extension (XS) code that gives perl access to the GSL (Gnu Scientific Library) ode solver.  It is self-contained in that the required part of the GSL library is copied into the XS bundle at compile time.

This was done to make the RHex executables as independent of dynamic libraries as possible, and thus more available to user who are not computer savvy. If the distributed code is incompatible with your machine, you will need to rebuild RichGSL.  The instructions for that are given below.  You will need to have the static libraries `libgsl` and `libgslcblas` available.  They can be downloaded from http://reflection.oss.ou.edu/gnu/gsl/.

There is a standard perl module `PerlGSL::DiffEq` available from CPAN that came earlier and does much the same thing, except that it's XS code dynamically links to the GSL libraries.

For WINDOWS, I was unable to make a static build and so needed to us the more usual dynamic linking procedure.  As it turned out, this was not a big problem since the dynamic library code for windows is much smaller than that for the mac, and the perl packing code that makes the standalone executable makes it easy to simply include the dynamic library in the executable package.

### The easy build

For the MAC, in the original distribution, the folder `RStaticLib` contains libraries `libgsl.a` and `libgslcblas.a`, and the libtool helper files `libgsl.la` and `libgslcblas.la` that run on the more recent Mac operating systems (eg, El Capitan).  If you think your system is compatible, simply run the shell script `RichGSL_MAKE_MAC.sh` from where it stands in the folder that contains this README.  If the build works, you're done.  `RichGSL` is installed in your perl library.

if the build doesn't work, you will need to download copies of these libraries built for your machine.  Go to the link mentioned above.  Replace the libraries in `RStaticLib` with the newly downloaded ones.  Run `RichGSL_MAKE.sh` again.

For WINDOWS, Strawberry PERL comes with the GSL libraries already installed.  If you are working in that environment, run `RichGSL_MAKE_WIN.cmd` from the directory in which it stands.


### Build from scratch

The perl distribution comes with binaries that to some extent automate the creation of XS modules. To produce the easy build described above, the procedure described below was carried out, which as a by-product, produced a template folder that can be used to directly build RichGSL. It is possible, but probably unlikely, that in some future version of PERL, changes might be made that make it necessary to remake the template folder. In that case, for the mac, you will need to carry out the following steps; for windows, do the analogous things, but you needn't create `RStaticLib`:

Start with the executable `h2xs`, which under perlbrew, is located in the bin folder directly under your perl version.

As in the easy build, download library files `libgsl.a`, `libgsl.la`, `libgslcblas.a`, and `libgslcblas.la` suited to your machine.

Then, suppose you want to work in a directory `RHex_XS`. For the mac, create a folder in `RHex_XS` named `RStaticLib`, and copy the downloaded library files into it. For windows you omit this step.  Then copy all the files in `RichGSL_Source` into `RHex_XS`.  

In Terminal, `cd` into `RHex_XS`, run

`h2xs -Afn RichGSL`

This makes a new folder `RichGSL`, with an elaborate set of subfolders, in `RHex_XS`. Among other things, it writes the file `RichGSL.pm` and puts it in the `lib` subfolder. The `RichGSL.pm` code is fine, but we want to install our pod documentation, so replace the created file by the one from source.

`cp RichGSL.pm RichGSL/lib/RichGSL.pm`

The next step should have been trivial, but due to an "incorrectable bug" in `h2xs`, you need to do something more elaborate. Run

```
cp rc_ode_solver_kluge.h RichGSL/rc_ode_solver.h
cp rc_ode_solver.c RichGSL/
```

Then for the mac run

`h2xs -Oxan RichGSL rc_ode_solver.h -L../RStaticLib -lgsl -lgslcblas`

and for windows run

`h2xs -Oxan RichGSL rc_ode_solver.h -lgsl -lgslcblas`

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
make
make test
make install
```
