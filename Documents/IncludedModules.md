```perl
use warnings;
use strict;

use Carp;

use Exporter 'import';
our @EXPORT = qw(DEBUG $verbose $debugVerbose $vs $tieMax %rSwingRunParams %rSwingRunControl $rSwingOutFileTag RSwingSetup LoadLine LoadLeader LoadDriver RSwingRun RSwingSave RSwingPlotExtras);

use Time::HiRes qw (time alarm sleep);
use Switch;
use File::Basename;
use Math::Spline;
use Math::Round;

use PDL;
    # Import main PDL module (see PDL.pm for equivalents).  In particular, imports PDL::Math, which redefines many POSIX math functions.  To get the original, call POSIX::aFunction.
use PDL::NiceSlice;
use PDL::AutoLoader;    # MATLAB-like autoloader.

use PerlGSL::DiffEq ':all';


use Carp;

use Exporter 'import';
our @EXPORT = qw( pq pqf pqInfo);

use warnings;
use strict;

use PDL;
# Import main PDL module (see PDL.pm for equivalents).  In particular, imports PDL::Math, which redefines many POSIX math functions.  To get the original, call POSIX::aFunction.
use PDL::NiceSlice;

#use Try::Tiny;

use PadWalker qw(peek_my);
#use Scalar::Util 'refaddr';
use Scalar::Util qw(refaddr looks_like_number);
use Data::Dump qw(dump);    # for testing

use POSIX ();
#require POSIX;
    # Require rather than use avoids the redefine warning when loading PDL.  But then I must always explicitly name the POSIX functions. See http://search.cpan.org/~nwclark/perl-5.8.5/ext/POSIX/POSIX.pod.  Implements a huge number of unixy (open ...) and mathy (floor ...) things.

use Carp;

use Exporter 'import';
our @EXPORT = qw( Plot PlotMat Plot3D);

use PDL;
use PDL::AutoLoader;    # MATLAB-like autoloader.
use PDL::NiceSlice;

use Chart::Gnuplot;
use Data::Dump;
use Scalar::Util qw(looks_like_number);


require Exporter;
@ISA	   = qw(Exporter);
@EXPORT    = qw(numjac);

use PDL;
use PDL::NiceSlice;
use PDL::Math;          # For isfinite, to detect nan.
use utf8;   # To help pp, which couldn't find it in require in AUTOLOAD.  This worked!

#use Tk 800.000;
use Tk;

# These are all the modules that we are using in this script.
use Tk::Frame;
use Tk::LabEntry;
use Tk::Optionmenu;
use Tk::FileSelect;
use Tk::TextUndo;
use Tk::Text;
use Tk::ROText;
use Tk::Scrollbar;
use Tk::Menu;
use Tk::Menubutton;
use Tk::Adjuster;
use Tk::DialogBox;

use Tk::Bitmap;     # To help pp
#use Tk::ErrorDialog;   # Uncommented, this actually causes die called elsewhere to produce a Tk dialog.

use Config::General;
use Switch;
use File::Basename;

use Try::Tiny;


se Time::HiRes qw (time alarm sleep);
use Switch;
use File::Basename;
use Math::Spline;
use Math::Round;

use PDL;
    # Import main PDL module (see PDL.pm for equivalents).  In particular, imports PDL::Math, which redefines many POSIX math functions.  To get the original, call POSIX::aFunction.

use PDL::NiceSlice;
use PDL::AutoLoader;    # MATLAB-like autoloader.
use PDL::Options;       # Good to keep in mind.


use Switch;

use PDL;
use PDL::AutoLoader;    # MATLAB-like autoloader.
use PDL::NiceSlice;
use PDL::Options;       # For iparse. http://pdl.perl.org/index.php?docs=Options&title=PDL::Options

use Chart::Gnuplot;


use Switch;
use Try::Tiny;
use Scalar::Util qw(looks_like_number);


use PDL;
    # Import main PDL module (see PDL.pm for equivalents).  In particular, imports PDL::Math, which redefines many POSIX math functions.  To get the original, call POSIX::aFunction.

use PDL::NiceSlice;     # Nice MATLAB-like syntax for slicing.
use PDL::AutoLoader;    # MATLAB-like autoloader.
use PDL::Options;     # Good to keep in mind. See RLM.

## Unsuccessful attempts to get a PDL spline:
#use PDL::GSL::INTERP;   # Spline interpolation, including deriv and integral.
#use PDL::Func;          # Includes an interpolation subroutine.   This almost works, but needs slatec for cubic.
#use PDL::Slatec;        # Needed for (hermite) cubic spline interpolation
#use PDL::Interpolate;
#use PDL::Interpolate::Slatec;

use Math::Spline;
    # Since I can't get PDL spline to work.  In any case, this provides trim access to splining.  See also RSpringFit.
```
