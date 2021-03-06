### PP_Usage

In Terminal, go to where the code is:

`cd /Users/richmiller/Active/Code/PERL/RHex`

To package RHexSwing3D.pl into the executable RHexSwing3D.  The `--compile` flag is necessary for `pp` to record stuff loaded at runtime:

`pp -o RHexSwing3D --compile RHexSwing.pl`

To run it, simply double-click in the Finder or from Terminal execute:

`./RHexSwing3D`

A few "use" modules were not found because they were autoloaded at runtime.  Simply "use" them explicitly.

And also:
`pp -o RHexReplot3D --compile RHexReplot3D.pl`

Multiple executables can be bundled together, and executed singly with link.

`pp -o RHexExe --compile RHexSwing3D.pl RHexReplot3D.pl`

In order to access the executables hidden in `RHexExe` you must make hard links:

```
ln RHexExe RHexSwing3D
ln RHexExe RHexReplot3D
```
You then double click on `RHexSwing3D` or `RHexReplot3D` to run.

PAR files are just .zip files, and so I put the above files in a folder along with any other files I want to send along -- documents, libraries, spec folders, and then use Mac compress.

Check out pp -l option, to link a file or a library into the packed file.

```
pp -o RHexSwing3DGSL -l gsl --compile RHexSwing3D.pl
pp -o RHexSwing3D --compile RHexSwing3D.pl
```

Use the `-p` flag.  This way you can look at the contents, including all resolved perl, but you don't get the executables

```
pp -p -o out.zip -c RHexSwing3D.pl
pp -p -o out.zip -a rgnuplotx -a rgnuplot -a _RUN_TEST.txt -c RHexReplot3D.pl
```
