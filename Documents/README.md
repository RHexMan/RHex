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

The first and simplest RHex option is to download the zip file RHexExe.zip that opens to a folder that contains executables that can be run directly from that folder.  People with no programming experience can use this option.  Once you have downloaded the .zip file, double click on it and it will create a folder with the same name.  Enter that folder and double click on either RHexSwing3D or, if you have previously saved swing output as text, double click on RHexReplot3D to run these programs.  The first time they open they may take several seconds to start.  Remember to checkout the Help menu in the upper right corner of the control pane. At the moment, this option is only available for somewhat modern macs running one of the more recent operating systems.

The second option is the usual open source method of downloading, and where necessary, compiling the source code. To use this option, it would be helpful to have at least a small anount of unix and PERL experience. You can check out XXXX to get enough to work with. Download or pull this entire repository.  You will then have to resolve the external dependencies.  Most of these are pure PERL, and may be easily resolved using perlbrew.  Complete instructions are given in the Perlbrew section below.  There is also one internal C-code dependency for the Gnu Scientific Library (GSL) ode solver (see https://www.gnu.org/software/gsl/doc/html/ode-initval.html), which is already resolved in the distribution.  If for some reason this does not work on your machine, this distribution contains the source static libraries `libgsl.a` and `libgslcblas.a` and the requisite makefile to recompile and relink.  See the section GSL ODE below for details.  Finally, all plotting is done via system calls to the gnuplot executable (see http://www.gnuplot.info/).  Again, for convenience, a copy of the gnuplot executable (`rgnuplot` and the meat `rgnuplotx`) are included in this distribution.  The programs will check if there is a system gnuplot, and use it if it is available.

### Perlbrew

Go online to https://perlbrew.pl/ and read about Perlbrew. 

Then see if your machine has the curl executable. It should be there since modern macs come with curl installed. Open a Terminal window. At the prompt type:

`which curl`

The response should be something like /usr/bin/curl, which means curl was found, and you're ok. Then download and install the latest perlbrew by coping and pasting the following line at the prompt:

`\curl -L https://install.perlbrew.pl | bash`

The self-install will write a few lines to the screen, including the following: Append the following piece of code to the end of your `~/.bash_profile` and start a new shell, perlbrew should be up and fully functional from there:

`source ~/perl5/perlbrew/etc/bashrc`

In your home directory (type `cd ~`) type `ls -a` to see a listing of the files.  One of them should be `.bash_profile`.  If it is not there, type `touch .bash_profile`.  Type  `open .bash_profile` to get a copy of the file in your usual text editor.  Copy and paste the line above, and hit save.  Close the file.  Then logout and log back in.  You should be set to go.

Download the latest perlbrew
Installing perlbrew

Using Perl </usr/bin/perl> perlbrew is installed: ~/perl5/perlbrew/bin/perlbrew

perlbrew root (~/perl5/perlbrew) is initialized.

Append the following piece of code to the end of your ~/.bash_profile and start a new shell, perlbrew should be up and fully functional from there:

source ~/perl5/perlbrew/etc/bashrc

Simply run perlbrew for usage details.

Happy brewing!

## Installing patchperl

## Done. Rich-Mac-mini-2016:~ rhexman$

Next, install the latest version of perl. At the terminal prompt copy and paste: perlbrew install perl-5.28.1

Make sure to have the new perl be the active one:

perlbrew switch perl-5.28.1

Check:

perlbrew info

Finally get cpanm. Copy and paste:

perlbrew install-cpanm

Generally, for help with perlbrew, type

perlbrew help



