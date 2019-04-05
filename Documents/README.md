### RHex - Fly fishing related dynamic simulations

Rich Miller,  4 April, 2019

The RHex project was created to make realistic dynamic computer simulations of interest to both fly fishers and fly rod builders.  It was preceded by the static Hexrod project of Wayne Cattanach, which was itself a computer updating in BASIC of the historical hand calculations of Garrison (see "A Master's Guide to Building a Bamboo Fly Rod", Everett Garrison and Hoagy B. Carmichael, first published in 1977).  Frank Stetzer translated Cattanach's code into CGI/Perl in 1997, and continues to maintain and upgrade it (www.hexrod.net).

RHex is written in PERL with heavy use of PDL and comprises two main programs, RHexCast and RHexSwing3D.  These programs allow very detailed user specification of the components.  The first simulates a complete aerial fly cast in a vertical plane, following motion of the rod, line, leader, tippet and fly caused by a user-specified motion of the rod handle.  The second simulates, in full 3D, the motion of the line, leader, tippet and fly, both in moving water and in still air above, caused by a user-specified motion of the rod tip.  This simulation speaks to the common fishing technique of swinging streamers, but is also applicable to the drifting of nymphs.

Each program has an interactive control panel that allows setting, saving, and retrieving of complex parameter sets, running the simulations, and plotting and saving the results, both as text and as static graphic files.  The primary outputs of these programs are 3D rotatable plots that show the rod and/or line as a sequence  of traces representing the configuration at equally spaced times. The earliest traces are shown in green and the latest in red, with the intermediate ones shown as brownish shades that are the combination of green and red in appropriate proportion.  Open circles, solid circles, diamonds and squares mark the locations of the rod tip, line-leader and leader-tippet junctions, and the fly.

An auxilliary program, RHexReplot3D, allows the replotting saved text data with a possibly different choice of line and point markers and reduced time range and frame rate. 

The control panel of each of the programs has a help menu in the upper left corner which gives access to a general discussion of the program as well as to detailed descriptions of the user-settable parameters, including their allowed and typical value ranges.

RHexCast and RHexSwing3D both make use of external files that allow nearly complete freedom to customize the details of the rod and line setup and driving motion.  The distribution includes a number of folders that organize these files and that contain samples.  Except for one sort of rod driving specification which requires a graphics editor, all the files are text, and can be opened, read and written with any standard text editor.  Each sample file has a header with explanatory information.  The idea is that when you want a modified file, you copy the original, make changes in your copy, and save it to the same folder.

### The Distributions

There are two ways to run the programs of the RHex project.  Both require you have XQuartz installed on your machine, since all the RHex graphics are drawn in X11 windows which are produced by XQuartz.  If you don't have XQuartz already, go to https://www.xquartz.org/ and click the download link.  Simple dialogs will lead you through the installation process.

The first and simplest RHex option is to download the zip file RHex_Exe.zip that opens to a folder that contains executables that can be run directly from that folder.  People with no programming experience can use this option.  Once you have downloaded the .zip file, double click on it and it will create a folder with the same name.  Enter that folder and double click on either RHexSwing3D or, if you have previously saved swing output as text, double click on RHexReplot3D to run these programs.  The first time they open they may take several seconds to start.  Remember to checkout the Help menu in the upper right corner of the control pane. At the moment, this option is only available for somewhat modern macs running one of the more recent operating systems.

The second option is the usual open source method of downloading, and where necessary, compiling the source code. To use this option, it would be helpful to have at least a small anount of unix and PERL experience. You can check out XXXX to get enough to work with. Download or pull this entire repository.  You will then have to resolve the external dependencies.  Most of these are pure PERL, and may be easily resolved using perlbrew.  Complete instructions are given in the Perlbrew section below.  There is also one internal C-code dependency for the Gnu Scientific Library (GSL) ode solver (see https://www.gnu.org/software/gsl/doc/html/ode-initval.html), which is already resolved in the distribution.  If for some reason this does not work on your machine, this distribution contains the source static libraries `libgsl.a` and `libgslcblas.a` and the requisite makefile to recompile and relink.  See the section GSL ODE below for details.  Finally, all plotting is done via system calls to the gnuplot executable (see http://www.gnuplot.info/).  Again, for convenience, a copy of the gnuplot executable (`rgnuplot` and the meat `rgnuplotx`) are included in this distribution.  The programs will check if there is a system gnuplot, and use it if it is available.

### Perlbrew

Go online to https://perlbrew.pl/ and read about Perlbrew. 

Then see if your machine has the curl executable. It should be there since modern macs come with curl installed. Open a Terminal window. At the prompt type:

`which curl`

The response should be something like /usr/bin/curl, which means curl was found, and you're ok. Then download and install the latest perlbrew by copying and pasting the following line at the prompt:

`\curl -L https://install.perlbrew.pl | bash`

The self-install will write a few lines to the screen, including the following: Append the following piece of code to the end of your `~/.bash_profile` and start a new shell, perlbrew should be up and fully functional from there:

`source ~/perl5/perlbrew/etc/bashrc`

To insert the code, go to your home directory by typing `cd ~`. Then type `ls -a` to see a listing of the files.  One of them should be `.bash_profile`.  If it is not there, type `touch .bash_profile`.  Type  `open .bash_profile` to get a copy of the file in your usual text editor.  Copy and paste the line above, and hit save.  Close the file.  Then logout and log back in.  You should be set to go.  Looking in your normal finder window, you will see a new folder `perl5`.  Everything that perlbrew subsequently put on your machine will go somewhere in that folder or its subfolders.

Next, install the latest version of perl. At the terminal prompt copy and paste:

`perlbrew install perl-5.28.1`

Perlbrew will write a few lines to the terminal, including: This could take a while. You can run the following command on another shell to track the status:

`tail -f ~/perl5/perlbrew/build.perl-5.28.1.log`

Use the Terminal Shell menu to open another tab, and copy and paste the above line, followed as always by the \<return\> key.  You can watch perlbrew work.  Eventually it will stop with the message `### brew finished ###`.  Go back to the original tab, where, if things went well you will see `perl-5.28.1 is successfully installed`.

At this point it is very important to make sure to have the new perl be the active one, since macs come with their own version of perl which we don't want to mess with.  Type:

`perlbrew switch perl-5.28.1`

Then check that the switch worked.  Type:

`perlbrew info`

Finally get `cpanm`, which is the executable that perlbrew works with to actually download code from the cloud. CPAN is the name of the online index that points to a huge amount of public domain PERL code.  Type:

`perlbrew install-cpanm`

Generally, for help with perlbrew, type

`perlbrew help`

At this point you have perlbrew and the most recent perl, and in addition the core perl libraries.  What's left is to install the small number of non-core perl packages that RHex uses.

### Cpanm

After the prompt copy and paste the long line below, then hit the \<return\> key: A lot of output should be generated, and sometimes nothing will seem to happen for a while, but eventually your prompt should re-appear. With luck there will be a message indicating success.

`cpanm PDL Config::General Switch Time::HiRes PadWalker Data::Dump Math::Spline Math::Round`

Download the Tk module, which constructs and implements the control panel. This download requires XQuartz to be installed first. Instructions for this were given above.  Type:

`cpanm Tk`

If you don't have the Command Line Tools executables, during this attempt, that will be noted, and you will be asked if you want to download them (see also addendum below). Say yes.  If successful, the tools will be put in the `/Library/Developer/CommandLineTools/` folder.  Try `cpanm Tk` again.

This attempt will fail, but just one of the final tests.  However, using the `--force` flag will bypass the test and let `Tk` install. I haven't found that the failed test causes a problem in the RHex applications. Type:

`cpanm Tk --force`

### Unix

As mentioned previously, RHex uses the public domain Gnuplot software to plot it output, so a `gnuplot` executable must be available on your machine. The distribution includes the files `rgnuplot` and `rgnuplotx` which together form a local copy of the required code.  If for some reason these don't work on your machine, you need to download and compile a version that does.








The GSL libraries `libgsl.a` and `libgslcblas.a` must also be present

which gnuplot

to see if one is there, and find out where it is. If the response to the above command is a path ending in the word .../gnuplot, the required executable is there.

The unix PATH variable may need be adjusted (in .bash_profile) to point to that location. Type: cpanm Chart::Gnuplot

Similarly, the GNU Scientific Library must also be available on the machine, and the appropriate library path must point to it. Type: cpanm PerlGSL::DiffEq



