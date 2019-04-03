AddUsingCpanm - Adding PERL modules (and their prerequisites).

Make sure that your newly installed perl is operative (otherwise the modules you install below will not go to the right place (in your ~/perl5 directory):

`perlbrew info`

And if it's not, type:

`perlbrew switch perl-5.28.1`

Open the mac Terminal application (Finder/Go/Utilities).  After the prompt copy and paste the following (long) line, then hit the <return> key:  A lot of output should be generated, sometimes nothing will seem to happen for a while, and eventually your prompt should re-appear.  With luck there will be a message indicating success.

Download and install most of the public domain modules that need to be included.  Type:
cpanm PDL Config::General Switch  Time::HiRes PadWalker Data::Dump Math::Spline Math::Round

Download the Tk module, which constructs and implements the control panel.  This download requires XQuartz to be installed first.  Go to https://www.xquartz.org/ and hit download.  Follow the subsequent high-level instructions.  Then try cpanm Tk.  If you don't have the Command Line Tools, during this attempt, that will be noted, and you will be asked if you want to download them (see also addendum below).  Say yes.  Then try cpanm Tk again.  This will fail one of the final tests, but using the --force flag will let it install.  I haven't found that the failed test causes a problem in the RHex applications.  Type:
cpanm Tk --force

gnuplot must be available on the machine.  type which gnuplot to see if it is there, and find out where it is.  The unix PATH variable may need be adjusted (in .bash_profile) to point to that location.  Type:
cpanm Chart::Gnuplot

Similarly, the GNU Scientific Library must also be available on the machine, and the appropriate library path must point to it. Type:
cpanm PerlGSL::DiffEq 


Addendum: For Command Line Tools (gcc, curl, git, etc), without XCode.  Good discussion, great trick if it still works:  http://osxdaily.com/2014/02/12/install-command-line-tools-mac-os-x/
In terminal type xcode-select --install.  When it doesn't work, it will say it needs the tools, do you want to download them.  Say yes, etc.  If successful, the tools will be in /Library/Developer/CommandLineTools/.



