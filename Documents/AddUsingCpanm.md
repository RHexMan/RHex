### Adding our required PERL modules and their prerequisites.

Working in a mac Terminal window...

Make sure that your newly installed perl (which for this example we shall assume is perl5.28.1) is current in perlbrew (otherwise the modules you install below will not go to the right place in your `~/perl5` directory.  At the prompt type:

`perlbrew info`

It should say it's using perl-5.28.1.  If it's not, type:

`perlbrew switch perl-5.28.1`

To download and install most of the public domain modules that need to be included, do the following:  After the prompt copy and paste the long line below, then hit the \<return\> key:  A lot of output should be generated, and sometimes nothing will seem to happen for a while, but eventually your prompt should re-appear.  With luck there will be a message indicating success.

`cpanm PDL Config::General Switch  Time::HiRes PadWalker Data::Dump Math::Spline Math::Round`

Download the Tk module, which constructs and implements the control panel.  This download requires XQuartz to be installed first.  Go to https://www.xquartz.org/ and hit download.  Follow the subsequent high-level instructions.  Then try

`cpanm Tk`

If you don't have the Command Line Tools, during this attempt, that will be noted, and you will be asked if you want to download them (see also addendum below).  Say yes.  Then try `cpanm Tk` again.

This will fail one of the final tests, but using the --force flag will let `Tk` install.  I haven't found that the failed test causes a problem in the RHex applications.  Type:

`cpanm Tk --force`

RHex uses the public domain Gnuplot software to plot it output, so a gnuplot executable must be available on your machine.  Type

`which gnuplot`

to see if one is there, and find out where it is. If the response to the above command is a path ending in the word  `.../gnuplot`, the required executable is there. 

The unix PATH variable may need be adjusted (in .bash_profile) to point to that location.  Type:
cpanm Chart::Gnuplot

Similarly, the GNU Scientific Library must also be available on the machine, and the appropriate library path must point to it. Type:
cpanm PerlGSL::DiffEq 


Addendum: For Command Line Tools (gcc, curl, git, etc), without XCode.  Good discussion, great trick if it still works:  http://osxdaily.com/2014/02/12/install-command-line-tools-mac-os-x/
In terminal type xcode-select --install.  When it doesn't work, it will say it needs the tools, do you want to download them.  Say yes, etc.  If successful, the tools will be in /Library/Developer/CommandLineTools/.


