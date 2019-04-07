### RHex - Fly fishing related dynamic simulations

Rich Miller,  6 April, 2019

The RHex project was created to make realistic dynamic computer simulations of interest to both fly fishers and fly rod builders.  It was preceded by the static Hexrod project of Wayne Cattanach, which was itself a computer updating in BASIC of the historical hand calculations of Garrison (see "A Master's Guide to Building a Bamboo Fly Rod", Everett Garrison and Hoagy B. Carmichael, first published in 1977).  Frank Stetzer translated Cattanach's code into CGI/Perl in 1997, and continues to maintain and upgrade it (www.hexrod.net).

RHex is written in PERL with heavy use of PDL and comprises two main programs, RHexCast and RHexSwing3D.  These programs allow very detailed user specification of rod and line components.  The first simulates a complete aerial fly cast in a vertical plane, following motion of the rod, line, leader, tippet and fly caused by a user-specified motion of the rod handle.  The second simulates, in full 3D, the motion of the line, leader, tippet and fly, both in moving water and in still air above, caused by a user-specified motion of the rod tip.  This simulation speaks to the common fishing technique of swinging streamers, but is also applicable to the drifting (dead or czech) of nymphs.

Each program has an interactive control panel that allows setting, saving, and retrieving of complex parameter sets, running the simulations, and plotting and saving the results, both as text and as static graphic files.  The primary outputs of these programs are 3D mouse-rotatable plots that show the rod and/or line as a sequence  of traces representing the component configuration at equally spaced times. The earliest traces are shown in green and the latest in red, with the intermediate ones shown in brownish shades that are the combination of green and red in appropriate proportion.  Open circles, solid circles, diamonds and squares mark the locations of the rod tip, line-leader and leader-tippet junctions, and the fly.

An auxilliary program, RHexReplot3D, allows the replotting of saved text data, with a possibly different choice of line and point markers and reduced time range and frame rate. 

The control panel of each of the programs has a help menu in the upper right corner which gives access to a general discussion of the program as well as to detailed descriptions of the user-settable parameters, including their allowed and typical value ranges.

RHexCast and RHexSwing3D both make use of external files that allow nearly complete freedom to customize the details of the rod and line setup and driving motion.  The distribution includes a number of folders that organize these files and that contain samples.  Except for one sort of rod driving specification which requires a graphics editor, all the files are text, and can be opened, read and written with any standard text editor.  Each sample file has a header with explanatory information.  The idea is that when you want a modified file, you copy the original, make changes in your copy, and save it, with a different name, to the same folder.

### The Distributions

There are two ways to run the programs of the RHex project.  Both require you to have XQuartz installed on your machine, since all the RHex graphics are drawn in X11 windows which are produced by XQuartz.  If you don't have XQuartz already, go to https://www.xquartz.org/ and click the download link.  Simple dialogs will lead you through the installation process.

The first and simpler RHex option is to download the zip file RHex_Exe.zip that opens to a folder that contains executables that can be run directly from that folder.  People with no programming experience can use this option.  Before downloading, mac users will need to go to __System Preferences / Security__ and select the radio button "Allow apps downloaded from __Anywhere__".  At the moment, this simple option is only available for somewhat modern macs running one of the more recent operating systems. Try it and see if it works for you.

Once you have downloaded the RHex_Exe.zip file, move it into your home folder.  Then double click on it to create a folder next to it named RHex_Exe. Once you have the new folder, you can delete the .zip file if you wish.  Enter RHex_Exe and double click on the file RHex_INSTALL.sh.  This will cause two new executables, RHexSwing3D and RHexReplot3D, to appear.  These are actually aliases to the file rhexexe, so they do not use up any more memory on your machine, but they let you access the functionality contained in rhexexe.  Double click on RHexSwing3D. When the control panel appears and stabilizes, hit the RUN button and wait.  Some text and a number of lines of dots and dahes will appear in the status window, and at some point, a plot window with the results of the run will pop up.  You can use the mouse to rotate the plot to any view you want.  Hover the cursor over the plot, click and hold, and drag.  Then release the mouse button.  Hit the SAVE OUT button, and then hit SAVE in the Save As dialog that appears.  This will store a copy of the output plot as a file in the RHex_Exe folder.  Next, double click on RHexReplot3D.  When its control panel stabilizes, hit the SELECT & LOAD button on the Source line.  In the navigator window that appears, double click on the \_Run... file you just created in the right hand window.  Then hit the PLOT button.  Your original plot will be reproduced in a new window. Note that the first time these programs open in a given session they may take several seconds to start. This is because the PERL interpreter has to do quite a bit of setup work.  However, it remembers some of this work for a while, so subsequent launches of the programs start more quickly.  Remember to check out the Help menu in the upper right corner of each of the control panels.

The second option is the usual open source method of downloading, and where necessary, compiling the source code. To use this option, it is helpful to have at least a small anount of unix and PERL experience, but even if you are a complete novice, with a little care and courage, you can follow the instructions below to a sucessful conclusion. If there is some text you don't understand, don't worry about it, but simply execute the highlighted commands, one at a time.

In all that follows, you will be dealing with the unix operating system that underlies all the Mac's normal, high-level behavior.  The Terminal applicaton is your window into unix.  To use Terminal, in the Finder select the __Go__ menu, and then choose the __Utilities__ folder.  Scroll down to near the bottom, where you will see Terminal.  Double click on it to get it started.  Alternatively, you can drag Terminal onto your Dock to place an alias to Terminal there (dragging to Dock does not move the original).  Thereafter, you can simply click of the Dock alias to launch the program.  When it launches, a rather plain window appears.  You type things in that window to interface with unix. See https://macpaw.com/how-to/use-terminal-on-mac for a brief introduction.

Download RHex as a .zip file or pull this entire repository and install them in your home folder.  You will then have to resolve the external dependencies.  Most of these are pure PERL, and may be easily resolved using perlbrew.  Complete instructions are given in the Perlbrew section below.  There is also one internal C-code dependency for the Gnu Scientific Library (GSL) ode solver (see https://www.gnu.org/software/gsl/doc/html/ode-initval.html), which is already resolved in the distribution.  If for some reason this does not work on your machine, you will need to reinstall the GSL Library from source, and then use the new library to resolve a local dependency.  See the section GSL ODE below for details.  Finally, all plotting is done via system calls to the gnuplot executable (see http://www.gnuplot.info/).  Again, for convenience, copies of the gnuplot and gnuplot_x11 executables are included in this distribution.  The programs will check if there is are system versions and use them if available.  Once you have finished all the downloading and compiling, go to the RHex folder and double click on RHexSwing3D.sh to run swing and on RHexReplot3D.sh to run replot.

### Perlbrew

Go online to https://perlbrew.pl/ and read about Perlbrew. 

Then see if your machine has the `curl` executable. It should be there since modern macs come with `curl` installed. Open a Terminal window. At the prompt type the commands highlighted below.  Note that, in general, each command you type in the Terminal window must be followed by hitting the \<return\> key.  The \<return\> tells the Terminal program that you want it to execute the command.  Also note that editing in the Termianl window is extremely simple-minded.  You can insert text only at the caret by typing, and delete text only by backdeleting over it.  You move the caret with the back and forward arrow keys.  In addition, you can select a block of previously typed text and then use copy and paste to insert it at the caret.  Type

`which curl`

The response should be something like `/usr/bin/curl`, which means `curl` was found, and you're ok. Then download and install the latest perlbrew by copying and pasting the following line at the prompt:

`\curl -L https://install.perlbrew.pl | bash`

The perlbrew self-install will write a few lines to the screen, including the following: "Append the following piece of code to the end of your `~/.bash_profile` and start a new shell, perlbrew should be up and fully functional from there"

`source ~/perl5/perlbrew/etc/bashrc`

To insert the code, go to your home directory by typing `cd ~`. Then type `ls -a` to see a listing of the files.  One of them should be `.bash_profile`.  If it is not there, type `touch .bash_profile`.  Type  `open .bash_profile` to get a copy of the file in your usual text editor.  Copy and paste the line above on its own line, and hit save.  Close the file.  Then logout from your computer and log back in.  You should be set to go.  Looking in your usual finder window, you will see a new folder `perl5`.  Everything that perlbrew subsequently puts on your machine will go somewhere in that folder or its subfolders.

Next, install the latest version of perl. At the terminal prompt copy and paste

`perlbrew install perl-5.28.1`

Perlbrew will write a few lines to the terminal, including: "This could take a while. You can run the following command on another shell to track the status."

`tail -f ~/perl5/perlbrew/build.perl-5.28.1.log`

Use the Terminal Shell menu to open another tab, and copy and paste the above line, followed as always by the \<return\> key.  You can watch perlbrew work.  Eventually it will stop with the message `### brew finished ###`.  Go back to the original tab, where, if things went well you will see `perl-5.28.1 is successfully installed`.

At this point it is very important to make sure that the new perl is the active one, since macs come with their own version of perl which we don't want to mess with.  Type

`perlbrew switch perl-5.28.1`

Then check that the switch worked.  Type

`perlbrew info`

Finally get `cpanm`, which is the executable that perlbrew works with to actually download code from the cloud. CPAN is the name of the online index that points to a huge amount of public domain PERL code.  Type

`perlbrew install-cpanm`

Generally, for help with perlbrew, type

`perlbrew help`

At this point you have perlbrew and the most recent perl, and in addition the core perl libraries.  What's left is to install the small number of non-core perl packages that RHex uses.

### Cpanm

After the prompt copy and paste the long line below, then hit \<return\>: A lot of output should be generated, and sometimes nothing will seem to happen for a while, but eventually your prompt should re-appear. With luck there will be a message indicating success.  This command takes so long because quite a few other modules, on which the listed ones depend, must also be loaded.  The power of programs like `cpanm` is that they do all the dirty work for you.

`cpanm PDL Config::General Switch Time::HiRes PadWalker Data::Dump Math::Spline Math::Round`

Download the Tk module, which constructs and implements the control panel. This download requires XQuartz to be installed first. Instructions for this were given above.  The Tk installation also requires the mac Command Line Tools.  To see if they have been installed, type

`which xcode-select`

If you have the tools, the answer will be `/usr/bin/xcode-select`.  If you don't see this, but just get your prompt back, type

`xcode-select --install`

You will be led through a sequence of steps that will complete the installation of the tools.  If successful, the tools will be put in the `/Library/Developer/CommandLineTools/` folder. Then you can type

`cpanm Tk --force`

Without the `--force` the load attempt will fail on one of the final tests.  However, using the `--force` flag will bypass the test and let `Tk` install. I haven't found that the failed test causes a problem in the RHex applications.

### Gnuplot

As mentioned previously, RHex uses the public domain Gnuplot software to plot its output, so a `gnuplot` executable must be available on your machine. The distribution includes its own copies of `gnuplot` and `gnuplot_x11`.  If for some reason they don't work on your machine, there are two things you can do.  The easier is to go to https://csml-wiki.northwestern.edu/index.php/Binary_versions_of_Gnuplot_for_OS_X and download and install binary versions.  This is completely automatic and will probably work just fine.  Or you can load and compile from source, which results in code that is more precisely tailored to your machine. Go to https://sourceforge.net/projects/gnuplot/ and press download.  Find the download `gnuplot-5.2.6.tar` on your machine and move it to your home folder.  Double click to unzip it, creating a folder of the same name.  Enter that folder and read the README for flavor and the beginning of the INSTALL text files.  In the first paragraph, the standard `./configure`, `make`, `make check`, `make install` sequence is noted.  Further down, there is a Mac OSX section, where it is explained that you should modify the `./configure` command.  So, in Terminal run the following commands, each line followed by its own \<return\>

```
cd` ~/gnuplot-5.2.6
./configure --with-readline=builtin
make
make check
sudo make install
```

The `make check` is really dramatic.  They flash lots of fancy plots before your eyes.  "Just look at the things gnuplot can do!"  Eventually the plots stop and you get your prompt back.  To do the install, you need to have administrator privileges and know the admin password.  The command sudo means that the following part of the command will be executed as super user.  When you hit \<return\>, you are immediately asked to enter your admin password.  If you enter it correctly and hit \<return\> again, the installation will proceed.  This extra bother is necessary since you are asking to install an executable function in privileged space, which, if you were a bad actor, could cause great problems. As the install proceeds, lots of scary looking output is produced, but hopefully, no actual error message.  To test whether the installation succeeded, type

`which gnuplot`

The answer should be `/usr/local/bin/gnuplot`.

### GSL ODE

Finally, an ordinary differential equations solver lies at the heart of our simulations, and the one we use comes from the Gnu Scientific Library.  In building the stand-alone executable RHexSwing3D, I incorporated a copy of the library into my RichGSL XS module, which is called from my perl module RUtils::DiffEq.  If, for some reason the integration does not work for you (you will know because pressing the run button on the RHexSwing3D control panel will fill the screen with error messages), you can download and compile your own copy of the library, and then incorporate it into RichGSL using the instructions below.  To begin, go to http://reflection.oss.ou.edu/gnu/gsl/, scroll to the bottom of the page, and click the link gsl-latest.tar.gz.  Put the downloaded .tar in your home folder, and proceed much as was described above for gnuplot.  Namely, double click to unzip, then scan the README and INSTALL files, in particular the part of the INSTALL file headed  "The simplest way to compile this package is:".  Run the following commands

```
cd gsl-2.5
./configure
make
make check
sudo make install
```

When the installation has completed you will find the GSL Library, which is actually actually a small collection of libraries, in `/usr/local/lib`.  Do the following:

```
cd /usr/local/lib
cp libgsl.a libgsl.la libgslcblas.a libgslcblas.la ~/RHex/RUtils/RStaticLib
cd ~/RHex/RUtils/RichGSL
make
make test
make install
```

If all this succeeds, RichGSL will be installed in an appropriate subdirectory of `~/perl5`.
