#!/usr/bin/env perl

# This shebang causes the first perl on the path to be used, which will be the perlbrew choice if using perlbrew.

# RHexCast3D.pl

#################################################################################
##
## RHex - 3D dyanmic simulation of fly casting and swinging.
## Copyright (C) 2019 Rich Miller <rich@ski.org>
##
## This file is part of RHex.
##
## RHex is free software: you can redistribute it and/or modify it under the
## terms of the GNU General Public License as published by the Free Software
## Foundation, either version 3 of the License, or (at your option) any later
## version.
##
## RHex is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
## without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
## PURPOSE.  See the GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License along with RHex.
## If not, see <https://www.gnu.org/licenses/>.
##
## RHex makes system calls to the Gnuplot executable, Copyright 1986 - 1993, 1998,
## 2004 Thomas Williams, Colin Kelley.  It makes static links to the Gnu Scientific
## Library, which is copyrighted and available under the GNU General Public License.
## In addition, RHex incorporates code from the Perl core and numerous Perl libraries,
## all of which are free software, redistributable and/or modifable under the same
## terms as Perl itself (Perl License).  Finally, the modules Brent, DiffEq, and
## Numjac in the directory RUtils are modifications and translations into Perl of
## copyrighted material.  You can find the details in the individual files.
##
##################################################################################

## If run with one arg, it is taken to be the .prefs file.  Generally, when loading, file navigation will start with the exe dir, and when saving, with the directory that holds the current settings file if there is one, otherwise with the exe dir.  That will encourage outputs associated with "related" settings to settle naturally in one folder.

# The code here is almost all boilerplate Tk. https://metacpan.org/pod/distribution/Tk/pod/UserGuide.pod

use warnings;
use strict;

our $VERSION='0.01';

our $OS;
our $program;
my $nargs;
our ($exeName,$exeDir,$basename,$suffix);
use File::Basename;

# https://perlmaven.com/argv-in-perl
# The name of the script is in [the perl variable] $0. The name of the program being
# executed, in the above case programming.pl, is always in the $0 variable of Perl.
# (Please note, $1, $2, etc. are unrelated!) 

BEGIN {	
	$exeName = $0;
	print "\nThis perl script was called as $exeName\n";
    
	($basename,$exeDir,$suffix) = fileparse($exeName,'.pl');
	#print "exeDir=$exeDir,basename=$basename,suffix=$suffix\n";	

	chdir "$exeDir";  # See perldoc -f chdir
	print "Working in $exeDir\n";
	
	$nargs = @ARGV;
    if ($nargs>1){die "\n$0: Usage:RHexReplot[.pl] [settingsFile]\n"}

	chomp($OS = `echo $^O`);
	print "System is $OS\n";

	$program = "RCast3D";
}

# Put the launch directory on the perl path. This needs to be here, outside and below the BEGIN block.
use lib ($exeDir);

use Carp;
use RCommon qw (DEBUG $verbose $debugVerbose %runControl);
use RCommonInterface;
use RCast3D qw ($rps);


# --------------------------------

use utf8;   # To help pp, which couldn't find it in require in AUTOLOAD.  This worked!
#use Tk 800.000;
use Tk;

# See https://www.tcl.tk/man/tcl8.4/TkCmd/text.htm
# Also, perldoc Tk::options

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
use Tk::Checkbutton;
use Tk::Adjuster;
use Tk::DialogBox;

use Tk::Bitmap;     # To help pp

use Config::General;
use Switch;     # WARNING: switch fails following an unrelated double-quoted string literal containing a non-backslashed forward slash.  This despite documentation to the contrary.
use File::Basename;

use RUtils::Print;
use RCommonPlot3D qw ( $gnuplot );

# See if gnuplot is installed:
if ($OS eq "MSWin32"){
	my $gnuplotPath;
	chomp($gnuplotPath = `where.exe  gnuplot`);
	if ($gnuplotPath){
		print "Using system gnuplot: $gnuplotPath\n";
		$gnuplot = "";
			# Call using the actual path name doesn't work in Chart::Gnuplot (??)
	} else {
		croak "ERROR: Unable to find an executable gnuplot on the system. Cannot proceed. You can download a self-installing version at https://sourceforge.net/projects/gnuplot/files/gnuplot/5.2.6/\n";
	}
} elsif ($OS eq "darwin") {	# Building for Mac
	# See if gnuplot and gnuplot_x11 are installed.  The latter is an auxilliary executable to manage the plots displayed in the X11 windows.  It is not necessary for the drawing of the control panel or the creation of the .eps files (see INSTALL in the Gnuplot distribution).  The system gnuplot is usually installed in  /usr/local/bin/ and it knows to look in /usr/local/libexed/gnuplot/versionNumber for gnuplot_x11:
	chomp($gnuplot = `which gnuplot`);
	if (!$gnuplot){
	#if (1){	# Force use of local version.
		print "Cannot find a system gnuplot, will try to use a local copy.\n";
		$gnuplot = $exeDir."/gnuplot";
		if (-e $gnuplot and -x $gnuplot) {
			my $gnuplot_x11 = $exeDir."/gnuplot_x11";
			if (-e $gnuplot_x11 and -x $gnuplot_x11) {
				$ENV{GNUPLOT_DRIVER_DIR} = "$exeDir";
					# This sets for this shell and its children (the forks that actually run gnuplot to make and maintain the plots, but does not affect the ancestors. GNUPLOT_DRIVER_DIR should definitely NOT be set and exported from .bash_profile, since that breaks the use of the system gnuplot and gnuplot_x11 if they could be found.
				print "Using gnuplot and gnuplot_x11 found in $exeDir.\n";
				} else {croak "ERROR: Unable to find a local gnuplot_x11 on the system, cannot proceed.\n"}
		} else {croak "ERROR: Unable to find an executable gnuplot on the system, cannot proceed.\n"}
	} else {print "Using system gnuplot $gnuplot\n"}
} else {die "ERROR: Unsupported systemt ($OS)\n"}

#use Tie::Watch;
    # Keep this in mind for general use.  However, for widgets, one can usually use the -validate and -validatecommand options to do what we want.
    # For redirecting STOUT when $verbose changes.  Maybe we can do this directly in TK.
#use Try::Tiny;  # Try to keep our validation from going away. DOESN'T WORK.

my $defaultSettingsFile = $rps->{file}{settings};
# Save a copy from startup values in RHexCastPkg.  During running of this program the value may be overwritten.


# Main Window
our $mw = new MainWindow;
$mw->geometry('1150x700+50+0');
$mw->resizable(0,0);

$runControl{callerUpdate}   = sub {$mw->update};
$runControl{callerStop}     = sub {OnStop()};
$runControl{callerRunState} = 0;   # 1 keep running, -1 pause, 0 stop.

$runControl{callerChangeVerbose}  = \&ChangeVerbose; # This is the right way.

# Menu Bar 

# This is the Tk 800.00 way to create a menu bar.  The
# menubar_menuitems() method returns an anonymous array containing all
# the information that is needed to create a menu.

my $mb = $mw->Menu(-menuitems=>&menubar_menuitems() );

# The configure command tells the main window to use this menubar;
# several menubars could be created and swapped in and out, if you
# wanted to.
$mw->configure(-menu=>$mb);


# Use the "Scrolled" Method to create widgets with scrollbars.

# The default key-bindings for the Text widgets and its derivatives
# TextUndo, and ROText are emacs-ish, e.g. ctrl-a cursor to beginning
# of line, ctrl-e, cursor to end of line, etc.

# The 'o' in 'osoe' means optionally, so when the widget fills up, the
# scrollbar will appear, otherwise we are binding the scrollbars to
# the 'south' side and to the 'east' side of the frame.

# Binding subs to events

# Every widget that is created in the Perl/Tk application either
# creates events or reacts to events.  

# Callbacks are subs that are used to react to events.  A callback is
# nothing more than a sub that is bound to a widget.

# The most common ways to bind a sub to an event are by using an
# anonymous sub with a call to your method inside it, such as in the
# following 'Key' bindings, or with a reference to the callback sub,
# as in the 'ButtonRelease' binding.


# CTRL-L, eval text widget contents 
$mw->bind('Tk::TextUndo', '<Control-Key-l>',
	  sub { OnEval(); } 
	  );

# CTRL-O, load a text file into the text widget 
$mw->bind('Tk::TextUndo', '<Control-Key-o>',
	  sub { OnFileOpen(); } 
	  );

# CTRL-S, save text as with file dialog
$mw->bind('Tk::TextUndo', '<Control-Key-s>',
	  sub { OnFileSave(); } 
	  );

# CTRL-Q, quit this application
$mw->bind('Tk::TextUndo', '<Control-Key-q>',
	  sub { OnExit(); } 
	  );



# Set up the widget frames:
our $files_fr     = $mw->Labelframe(-text=>"Files")->pack(qw/-side top -fill both -expand 1/);
our $params_fr       = $mw->Frame->pack(qw/-side top -fill both -expand 1/);
my $rod_fr          = $params_fr->Labelframe(-text=>"Rod")->pack(qw/-side left -fill both -expand 1/);
my $line_fr         = $params_fr->Labelframe(-text=>"Rod Material & Line")->pack(qw/-side left -fill both -expand 1/);
my $tip_fr          = $params_fr->Labelframe(-text=>"Leader, Tippet & Fly")->pack(qw/-side left -fill both -expand 1/);
my $ambient_fr      = $params_fr->Labelframe(-text=>"Ambient, Initial Config\n& Tip Release")->pack(qw/-side left -fill both -expand 1/);
my $driver_fr        = $params_fr->Labelframe(-text=>"Handle Motion")->pack(qw/-side left -fill both -expand 1/);
my $int_fr          = $params_fr->Labelframe(-text=>"Integration, Etc")->pack(qw/-side left -fill both -expand 1/);

my $run_fr       = $mw->Labelframe(-text=>"Execution")->pack(qw/-side bottom -fill both -expand 1/);

# Need to put the status widget def before the verbose entry that tries to link to it:
# Set up the rest of the run frame contents ---------
$run_fr->Label(-text=>"Status")->grid(-row=>0,-column=>0);       
my $status_scrl = $run_fr->Scrolled('ROText',
                -relief=>'groove',
                -height=>'8',
                -width=>'120',
                -scrollbars=>'oe',
			     )->grid(-row=>1,-column=>0,-columnspan=>5); ;        

$run_fr->Label(-text=>" ")->grid(-row=>2,-column=>2);       

# The Text widget has a TIEHANDLE module implemented so that we can tie the text widget to STDOUT for print and printf;  NOTE that since we used the "Scrolled" method to create our text widget, we have to get a reference to it and pass that to "tie", otherwise it won't work.

our $status_rot = $status_scrl->Subwidget("rotext");  # Needs to be lowercase!(?)


# Set up the files frame contents -----
    $files_fr->LabEntry(-state=>'readonly',-relief=>'groove',-textvariable=>\$rps->{file}{settings},-label=>'Settings',-labelPack=>[qw/-side left/],-width=>100)->grid(-row=>0,-column=>0,-sticky=>'e');
    $files_fr->Button(-text=>'Select & Load',-command=>sub{OnSettingsSelect(),-height=>'0.5'})->grid(-row=>0,-column=>1);
    $files_fr->Button(-text=>'None',-command=>sub{OnSettingsNone(),-height=>'0.5'})->grid(-row=>0,-column=>2);

    $files_fr->LabEntry(-state=>'readonly',-relief=>'groove',-textvariable=>\$rps->{file}{rod},-label=>'Rod',-labelPack=>[qw/-side left/],-width=>100)->grid(-row=>1,-column=>0,-sticky=>'e');
    $files_fr->Button(-text=>'Select',-command=>sub{OnRodSelect(),-height=>'0.5'})->grid(-row=>1,-column=>1);
    $files_fr->Button(-text=>'None',-command=>sub{OnRodNone(),-height=>'0.5'})->grid(-row=>1,-column=>2);

    $files_fr->LabEntry(-state=>'readonly',-relief=>'groove',-textvariable=>\$rps->{file}{line},-label=>'Line',-labelPack=>[qw/-side left/],-width=>100)->grid(-row=>2,-column=>0,-sticky=>'e');
    $files_fr->Button(-text=>'Select',-command=>sub{OnLineSelect(),-height=>'0.5'})->grid(-row=>2,-column=>1);
    $files_fr->Button(-text=>'None',-command=>sub{OnLineNone(),-height=>'0.5'})->grid(-row=>2,-column=>2);

    $files_fr->LabEntry(-state=>'readonly',-relief=>'groove',-textvariable=>\$rps->{file}{driver},-label=>'Cast',-labelPack=>[qw/-side left/],-width=>100)->grid(-row=>3,-column=>0,-sticky=>'e');
    $files_fr->Button(-text=>'Select',-command=>sub{OnDriverSelect(),-height=>'0.5'})->grid(-row=>3,-column=>1);
    $files_fr->Button(-text=>'None',-command=>sub{OnDriverNone(),-height=>'0.5'})->grid(-row=>3,-column=>2);


# Set up the rod frame contents -----
our @rodFields;

    $rod_fr->LabEntry(-textvariable=>\$rps->{rod}{numSegs},-label=>'numSegs',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>0,-column=>0,-sticky=>'e');
    $rod_fr->LabEntry(-textvariable=>\$rps->{rod}{segExponent},-label=>'segExponent',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>1,-column=>0,-sticky=>'e');
    $rodFields[0] = $rod_fr->LabEntry(-textvariable=>\$rps->{rod}{rodLenFt},-label=>'rodLen(ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>2,-column=>0,-sticky=>'e');
    $rodFields[1] = $rod_fr->LabEntry(-textvariable=>\$rps->{rod}{actionLenFt},-label=>'actionLen(ft))',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>3,-column=>0,-sticky=>'e');
    $rodFields[2] = $rod_fr->LabEntry(-textvariable=>\$rps->{rod}{numSections},-label=>'numSections',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>4,-column=>0,-sticky=>'e');
    my @aSectionItems = ("section - hex","section - square","section - round");
    $rodFields[3] = $rod_fr->Optionmenu(-options=>\@aSectionItems,-variable=>\$rps->{rod}{sectionItem},-textvariable=>\$rps->{rod}{sectionName},-relief=>'sunken')->grid(-row=>5,-column=>0,-sticky=>'e');
    $rodFields[4] = $rod_fr->LabEntry(-textvariable=>\$rps->{rod}{buttDiamIn},-label=>'buttDiam(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>6,-column=>0,-sticky=>'e');
    $rodFields[5] = $rod_fr->LabEntry(-textvariable=>\$rps->{rod}{tipDiamIn},-label=>'tipDiam(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>7,-column=>0,-sticky=>'e');
    $rod_fr->LabEntry(-textvariable=>\$rps->{rod}{fiberGradient},-label=>'fiberGrad(1/in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>8,-column=>0,-sticky=>'e');
    $rod_fr->LabEntry(-textvariable=>\$rps->{rod}{maxWallThicknessIn},-label=>'maxWallThick(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>9,-column=>0,-sticky=>'e');
    $rod_fr->LabEntry(-textvariable=>\$rps->{rod}{ferruleKsMult},-label=>'ferruleKsMult',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>10,-column=>0,-sticky=>'e');
    $rod_fr->LabEntry(-textvariable=>\$rps->{rod}{vAndGMultiplier},-label=>'vAndGMult(oz/in^2)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>11,-column=>0,-sticky=>'e');

# Set up the rod materials-line frame contents -----
our @lineFields;

    $line_fr->LabEntry(-textvariable=>\$rps->{rod}{densityLbFt3},-label=>'rodDensity(lb/ft3)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>0,-column=>0,-sticky=>'e');
    $line_fr->LabEntry(-textvariable=>\$rps->{rod}{elasticModulusPSI},-label=>'elasticMod(psi)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>1,-column=>0,-sticky=>'e');
    $line_fr->LabEntry(-textvariable=>\$rps->{rod}{dampingModulusStretchPSI},-label=>'dampModStretch(psi)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>2,-column=>0,-sticky=>'e');
    $line_fr->LabEntry(-textvariable=>\$rps->{rod}{dampingModulusBendPSI},-label=>'dampModBend(psi)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>3,-column=>0,-sticky=>'e');
    $line_fr->Label(-text=>'',-width=>8)->grid(-row=>4,-column=>0,-sticky=>'e');

    $line_fr->LabEntry(-textvariable=>\$rps->{line}{numSegs},-label=>'lineNumSegs
(all components)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>5,-column=>0,-sticky=>'e');
    $line_fr->LabEntry(-textvariable=>\$rps->{line}{segExponent},-label=>'segExponent',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>6,-column=>0,-sticky=>'e');
    $line_fr->LabEntry(-textvariable=>\$rps->{line}{activeLenFt},-label=>'activeFlyLine(ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>7,-column=>0,-sticky=>'e');
    $line_fr->LabEntry(-textvariable=>\$rps->{line}{nomWtGrsPerFt},-label=>'nominalWt(gr/ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>8,-column=>0,-sticky=>'e');
    $lineFields[0] = $line_fr->LabEntry(-textvariable=>\$rps->{line}{estimatedDensity},-label=>'estimatedDensity',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>9,-column=>0,-sticky=>'e');
    $lineFields[0] = $line_fr->LabEntry(-textvariable=>\$rps->{line}{nomDiameterIn},-label=>'nomDiam(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>10,-column=>0,-sticky=>'e');
    $lineFields[1] = $line_fr->LabEntry(-textvariable=>\$rps->{line}{coreDiameterIn},-label=>'coreDiam(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>11,-column=>0,-sticky=>'e');
    $line_fr->LabEntry(-textvariable=>\$rps->{line}{coreElasticModulusPSI},-label=>'coreElasticMod(psi)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>12,-column=>0,-sticky=>'e');
    $line_fr->LabEntry(-textvariable=>\$rps->{line}{dampingModulusPSI},-label=>'dampingMod(psi)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>13,-column=>0,-sticky=>'e');

# Set up the tippet_fly frame contents -----
our @leaderFields;

    my @aLeaderItems = ("leader - level","leader - 7ft 5x","leader - 10ft 3x");
    $leaderFields[0] = $tip_fr->Optionmenu(-options=>\@aLeaderItems,-variable=>\$rps->{leader}{idx},-textvariable=>\$rps->{leader}{text},-relief=>'sunken')->grid(-row=>0,-column=>0,-sticky=>'e');
    $leaderFields[1] = $tip_fr->LabEntry(-textvariable=>\$rps->{leader}{lenFt},-label=>'leaderLen(ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>1,-column=>0,-sticky=>'e');
    $leaderFields[2] = $tip_fr->LabEntry(-textvariable=>\$rps->{leader}{wtGrsPerFt},-label=>'leaderWt(gr/ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>2,-column=>0,-sticky=>'e');
    $leaderFields[3] = $tip_fr->LabEntry(-textvariable=>\$rps->{leader}{diamIn},-label=>'leaderDiam(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>3,-column=>0,-sticky=>'e');
    $leaderFields[4] = $tip_fr->LabEntry(-textvariable=>\$rps->{leader}{coreDiamIn},-label=>'leaderCoreDiam(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>4,-column=>0,-sticky=>'e');
    $tip_fr->Label(-text=>'',-width=>8)->grid(-row=>5,-column=>0,-sticky=>'e');

    my @aTippetItems = ("tippet - mono","tippet - fluoro");
    $tip_fr->Optionmenu(-options=>\@aTippetItems,-variable=>\$rps->{tippet}{idx},-textvariable=>\$rps->{line}{text},-relief=>'sunken')->grid(-row=>6,-column=>0,-sticky=>'e');
    $tip_fr->LabEntry(-textvariable=>\$rps->{tippet}{lenFt},-label=>'tippetLen(ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>7,-column=>0,-sticky=>'e');
    $tip_fr->LabEntry(-textvariable=>\$rps->{tippet}{diamIn},-label=>'tippetDiam(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>8,-column=>0,-sticky=>'e');
    $tip_fr->Label(-text=>'',-width=>8)->grid(-row=>9,-column=>0,-sticky=>'e');

    $tip_fr->LabEntry(-textvariable=>\$rps->{fly}{wtGr},-label=>'flyWeight(gr)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>10,-column=>0,-sticky=>'e');
    $tip_fr->LabEntry(-textvariable=>\$rps->{fly}{nomDiamIn},-label=>'flyNomDiam(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>11,-column=>0,-sticky=>'e');
    $tip_fr->LabEntry(-textvariable=>\$rps->{fly}{nomLenIn},-label=>'flyNomLen(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>12,-column=>0,-sticky=>'e');


# Set up the ambient and initialization frame contents -----
    $ambient_fr->LabEntry(-textvariable=>\$rps->{ambient}{gravity},-label=>'gravity',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>0,-column=>0,-sticky=>'e');
    $ambient_fr->LabEntry(-textvariable=>\$rps->{ambient}{dragSpecsNormal},-label=>'CDragSpecsNorm',-labelPack=>[qw/-side left/],-width=>10)->grid(-row=>1,-column=>0,-sticky=>'e');
    $ambient_fr->LabEntry(-textvariable=>\$rps->{ambient}{dragSpecsAxial},-label=>'CDragSpecsAxial',-labelPack=>[qw/-side left/],-width=>10)->grid(-row=>2,-column=>0,-sticky=>'e');
    $ambient_fr->Label(-text=>'',-width=>8)->grid(-row=>3,-column=>0,-sticky=>'e');

    $ambient_fr->LabEntry(-textvariable=>\$rps->{rod}{totalThetaDeg},-label=>'rodTotalTheta(deg)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>4,-column=>0,-sticky=>'e');
    $ambient_fr->LabEntry(-textvariable=>\$rps->{line}{angle0Deg},-label=>'rodTipToFlyAngle(deg)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>5,-column=>0,-sticky=>'e');
    $ambient_fr->LabEntry(-textvariable=>\$rps->{line}{curve0InvFt},-label=>'lineCurve0(1/ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>6,-column=>0,-sticky=>'e');
    $ambient_fr->Label(-text=>'',-width=>8)->grid(-row=>7,-column=>0,-sticky=>'e');

    $ambient_fr->LabEntry(-textvariable=>\$rps->{holding}{releaseDelay},-label=>'holdReleaseDelay',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>8,-column=>0,-sticky=>'e');
    $ambient_fr->LabEntry(-textvariable=>\$rps->{holding}{releaseDuration},-label=>'releaseDuration',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>9,-column=>0,-sticky=>'e');
    $ambient_fr->LabEntry(-textvariable=>\$rps->{holding}{springConstant},-label=>'holdSpringConst',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>10,-column=>0,-sticky=>'e');
    $ambient_fr->LabEntry(-textvariable=>\$rps->{holding}{dampingConstant},-label=>'holdDampingConst',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>11,-column=>0,-sticky=>'e');


# Set up the driver frame contents ------
our @driverFields;

    $driverFields[0] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{powerStartCoordsIn},-label=>'powerStart(in)',-labelPack=>[qw/-side left/],-width=>11)->grid(-row=>0,-column=>0,-sticky=>'e');
    $driverFields[1] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{powerEndCoordsIn},-label=>'powerEnd(in)',-labelPack=>[qw/-side left/],-width=>11)->grid(-row=>1,-column=>0,-sticky=>'e');
    $driverFields[2] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{powerPivotCoordsIn},-label=>'powerPivot(in)',-labelPack=>[qw/-side left/],-width=>11)->grid(-row=>2,-column=>0,-sticky=>'e');
    $driverFields[3] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{powerCurvInvIn},-label=>'powerMeanCurv(1/in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>3,-column=>0,-sticky=>'e');
	$driverFields[4] =  $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{powerSkewness},-label=>'powerTrackSkew',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>4,-column=>0,-sticky=>'e');
    $driverFields[5] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{powerWristStartDeg},-label=>'powerWristStart(deg)',-labelPack=>[qw/-side left/],-width=>11)->grid(-row=>5,-column=>0,-sticky=>'e');
    $driverFields[6] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{powerWristEndDeg},-label=>'powerWristEnd(deg)',-labelPack=>[qw/-side left/],-width=>11)->grid(-row=>6,-column=>0,-sticky=>'e');
	$driverFields[7] =  $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{powerWristSkewness},-label=>'powerWristSkew',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>7,-column=>0,-sticky=>'e');
    $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{powerStartTime},-label=>'powerStartTime(sec)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>8,-column=>0,-sticky=>'e');
    $driverFields[8] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{powerEndTime},-label=>'powerEndTime(sec)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>9,-column=>0,-sticky=>'e');
    $driverFields[9] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{powerVelSkewness},-label=>'powerVelSkew',-labelPack=>[qw/-side left/],-width=>9)->grid(-row=>10,-column=>0,-sticky=>'e');
    $driverFields[10] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{driftWristEndDeg},-label=>'driftWristEnd(deg)',-labelPack=>[qw/-side left/],-width=>11)->grid(-row=>11,-column=>0,-sticky=>'e');
    $driverFields[11] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{driftStartTime},-label=>'driftStartTime(sec)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>12,-column=>0,-sticky=>'e');
    $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{driftEndTime},-label=>'driftEndTime(sec)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>13,-column=>0,-sticky=>'e');
	$driverFields[12] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{driftVelSkewness},-label=>'driftVelSkew',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>14,-column=>0,-sticky=>'e');
    $driver_fr->Checkbutton(-variable=>\$rps->{driver}{showTrackPlot},-text=>'showTrackPlot',-anchor=>'center',-offrelief=>'groove')->grid(-row=>15,-column=>0);

=begin comment

$driver_fr->LabEntry(-textvariable=>\$rps->{driver}{plotSplines},-label=>'plotSplines',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>14,-column=>0,-sticky=>'e');

=end comment

=cut



# Set up the integration frame contents -----

    $int_fr->LabEntry(-textvariable=>\$rps->{integration}{t0},-label=>'t0',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>0,-column=>0,-sticky=>'e');
    $int_fr->LabEntry(-textvariable=>\$rps->{integration}{t1},-label=>'t1',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>1,-column=>0,-sticky=>'e');
    $int_fr->LabEntry(-textvariable=>\$rps->{integration}{dt0},-label=>'dt0',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>2,-column=>0,-sticky=>'e');
    $int_fr->LabEntry(-textvariable=>\$rps->{integration}{minDt},-label=>'minDt',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>3,-column=>0,-sticky=>'e');
    $int_fr->LabEntry(-textvariable=>\$rps->{integration}{plotDt},-label=>'plotDt',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>4,-column=>0,-sticky=>'e');
    my @aStepperItems = ("msbdf_j","rk4imp_j","rk2imp_j","rk1imp_j","bsimp_j","rkf45","rk4","rk2","rkck","rk8pd","msadams");
    $int_fr->Optionmenu(-options=>\@aStepperItems,-variable=>\$rps->{integration}{stepperItem},-textvariable=>\$rps->{integration}{stepperName},-relief=>'sunken')->grid(-row=>5,-column=>0,-sticky=>'e');
    $int_fr->Label(-text=>'',-width=>8)->grid(-row=>6,-column=>0,-sticky=>'e');

    my $saveOptionsMB = $int_fr->Menubutton(-state=>'normal',-text=>'saveOptions',-relief=>'sunken',-direction=>'below',-width=>12)->grid(-row=>7,-column=>0,-sticky=>'e');
        my $saveOptionsMenu = $saveOptionsMB->Menu();
            $saveOptionsMenu->add('checkbutton',-label=>'plot',-variable=>\$rps->{integration}{savePlot});        
            $saveOptionsMenu->add('checkbutton',-label=>'data',-variable=>\$rps->{integration}{saveData});    
        $saveOptionsMB->configure(-menu=>$saveOptionsMenu);   # Attach menu to button.
	$int_fr->Label(-text=>'',-width=>8)->grid(-row=>8,-column=>0,-sticky=>'e');

our @verboseFields;

	my @aVerboseItems;
	# I'm kluging the labeling, since setting the LabEntry items to 'normal' makes the content black (and writable) but leaves the label gray:
    if (DEBUG){
		my @aDebugVerboseItems = ("debugVerbose - 3","debugVerbose - 4","debugVerbose - 5","debugVerbose - 6");
		$verboseFields[1] = $int_fr->Optionmenu(-command=>sub {OnDebugVerbose()},-options=>\@aDebugVerboseItems,-textvariable=>\$rps->{integration}{debugVerboseName},-relief=>'sunken')->grid(-row=>9,-column=>0,-sticky=>'e');
		
		@aVerboseItems = ("verbose - 0","verbose - 1","verbose - 2","verbose - 3","verbose - 4","verbose - 5","verbose - 6");
		$verboseFields[0] = $int_fr->Optionmenu(-command=>sub {OnVerbose()},-options=>\@aVerboseItems,-textvariable=>\$rps->{integration}{verboseName},-relief=>'sunken')->grid(-row=>10,-column=>0,-sticky=>'e');
	} else {
        $debugVerbose = 3;  # The only thing that makes sense in this situation.
		
		@aVerboseItems = ("verbose - 0","verbose - 1","verbose - 2","verbose - 3");
		$verboseFields[0] = $int_fr->Optionmenu(-command=>sub {OnVerbose()},-options=>\@aVerboseItems,-textvariable=>\$rps->{integration}{verboseName},-relief=>'sunken')->grid(-row=>9,-column=>0,-sticky=>'e');
	}




# Set up the rest of the run frame contents ---------
my $quit_btn  = $run_fr->Button(-text=>'Quit',-command=>sub{OnExit()}
        )->grid(-row=>3,-column=>0);
$run_fr->Button(-text=>'Save Settings',-command=>sub{OnSaveSettings()}
        )->grid(-row=>3,-column=>1);
our $runPauseCont_btn  = $run_fr->Button(-text=>'RUN',-command=>sub{OnRunPauseCont()}
        )->grid(-row=>3,-column=>2);
$run_fr->Button(-text=>'Stop',-command=>sub{OnStop()}
        )->grid(-row=>3,-column=>3);
$run_fr->Button(-text=>'Save Out',-command=>sub{OnSaveOut()}
        )->grid(-row=>3,-column=>4);



# Establish the initial settings:
my $ok = 0;
my $filename = $rps->{file}{settings};
if ($filename){
    $ok = LoadSettings($filename);
    if (!$ok){warn "Could not load settings from $filename.\n"}
}
if (!$ok){
    $filename = $defaultSettingsFile;
    $ok = LoadSettings($filename);
    if (!$ok){warn "Could not load default settings from $filename.\n"}
}
if (!$ok){
    $filename = "";
    warn "Unable to find good setings file, using built-in settings.\n\n";
}
$rps->{file}{settings} = $filename;
UpdateFieldStates();

# Make sure required side effects of (re)setting verbose are done:
OnVerbose();
if (DEBUG){OnDebugVerbose()};


# Start the main event loop
MainLoop;

exit 0;


sub UpdateFieldStates {
    
    if ($rps->{file}{rod}){SetFields(\@rodFields,"-state","disabled")}
    else {SetFields(\@rodFields,"-state","normal")}
    
   if ($rps->{file}{line}){SetFields(\@lineFields,"-state","disabled")}
    else {SetFields(\@lineFields,"-state","normal")}
    
    if ($rps->{file}{leader}){SetFields(\@leaderFields,"-state","disabled")}
    else {SetFields(\@leaderFields,"-state","normal")}
    
    if ($rps->{file}{driver}){SetFields(\@driverFields,"-state","disabled")}
    else {SetFields(\@driverFields,"-state","normal")}
    
}



# return an anonymous list of lists describing the menubar menu items
sub menubar_menuitems
{
    return 
	[ map 
	  ['cascade', $_->[0], -tearoff=> 0,
	   -menuitems=>$_->[1]],

	  # make sure you put the parens here because we want to
	  # evaluate and not just store a reference
	  ['~File', &file_menuitems()],
	  ['~Help', &help_menuitems()],
	];
}

sub file_menuitems
{

# 'command', tells the menubar that this is not a label for a sub
# menu, but a binding to a callback; the alternate here is 'cascade'
# Try uncommenting the following code to create an 'Operations' sub
# menu in the main 'File' menu.

    return
	[
	 [qw/command ~Open  -accelerator Ctrl-o/,
	  -command=>[\&OnFileOpen]],
	 [qw/command ~Save  -accelerator Ctrl-s/,
	  -command=>[\&OnFileSave]],
	 '',
	 [qw/command E~xit  -accelerator Ctrl-q/,
	  -command=>[\&OnExit]],
	 ];
}

sub help_menuitems
{
    return
	[
	 ['command', 'About', -command=>[\&OnAbout]],
	 ['command', 'COPYRIGHT & LICENSE', -command=>[\&OnLicense]],
	 ['command', 'Params-Rod', -command=>[\&OnRod]],
	 ['command', 'Params-Line,Etc', -command=>[\&OnLineEtc]],
	 ['command', 'Params-Ambient,Etc', -command=>[\&OnAmbientEtc]],
	 ['command', 'Params-HandleMotion', -command=>[\&OnHandleMotion]],
	 ['command', 'Params-Integ,Etc', -command=>[\&OnIntegEtc]],
	 ['command', 'Params-Verbose', -command=>[\&OnVerboseParam]],
	 ['command', 'Gnuplot View', -command=>[\&OnGnuplotView]],
	 ['command', 'Gnuplot View (cont)', -command=>[\&OnGnuplotViewCont]],
	];
}

# Here is our "Exit The Application" callback method. :-)
sub OnExit { 
    exit 0; 
}


# Show the Help->About Dialog Box
sub OnAbout {
    # Construct the DialogBox
    my $about = $mw->DialogBox(
		   -title=>"About",
		   -buttons=>["OK"]
		   );

    # Now we need to add a Label widget so we can show some text.  The
    # DialogBox is essentially an empty frame with no widgets in it.
    # You can images, buttons, text widgets, listboxes, etc.
    $about->add('Label',
		-anchor=>'w',
		-justify=>'left',
		-text=>qq(
RHexCast3D 0.01 - Rich Miller, 2019

This is a program that simulates the motion of a rod and multi-component fly line (line proper, leader,
tippet and fly) during a cast under the influence of gravity, air friction and internal stresses.  The
cast is driven by a user defined motion of the rod handle.  User definition also sets the initial
configuration of the rod and line.
	
The results of the calculation are displayed as constant-time-interval colored traces on a 3D plot
that can be rotated at will by the motion of the cursor.  The earliest traces are shown in green and
the latest in red, with the intermediate traces shown as brownish shades that are the combination of
green and red in appropriate proportion.  Open circles, solid circles, diamonds and squares mark the
locations of the rod tip, line-leader and leader-tippet junctions, and the fly.
    
The interactive control panel allows the setting of parameters that control the details of the rod
and line make-up, the initial rod and line configuration, the rod handle movement, and instructions
for integration and plotting.  In addition, the panel allows for the selection of a parameter
preference file, which presets all the parameters to a previously saved condition, as well as the
selection of files that define a specific rod, fly-line and handle motion.  Use of the rot, line and
motion files allows the simulation of any fly line with any motion, not just those constructable using
the parameters.
    
Once you have set the parameters to your liking, press the run button to begin the computation at
the nominal start time (t0).  The report interval (plotDt) sets the times at which traces are drawn.
When the run starts, the parameters are range-checked for validity.  Range violations that preclude
program execution generate error messages.  You must correct these errors and try again.  Other
settings, that merely are outside the usual expected range, generate warnings that tell you what
the expected range is, but do no stop the run.  You can stop it yourself and make changes if you
want.
    
Depending on the value of the special parameter verbose, more or less runtime output will be shown.
Verbose = 0 shows only the run identifier and any errors which stop the run.  Verbose = 1 shows
warnings as well as errors, and also a few of the major mileposts of the computation.  Verbose = 2
shows all these things as well as showing the progress in nominal time and giving an indication of
how much work the integrator needs to do to get from one reported time step to the next.  This is
probably the best general setting.  You get a good feel for how the computation is going, without
causing it to slow down very much.  At any time, you can press the pause button to get the output
plot as of that time.  If you subsequently hit the continue button, the calculation will resume at
the last reliable plotted time, which is the last one at one of the uniform steps.

The design of the program requires that the parameters that define a run cannot be changed during
the run.  Thus, when a run starts, all the control panel parameters are grayed out, indicating that
fact.  When a run is paused, the parameters remain gray except for verbose, which turns black
and accepts changes.  This doesn\'t violate the design requirement, since changing verbose does not
change the calculation in any way, but only changes what details of the calculation are displayed.
This feature turns out to be very useful, since if you want to look at details later in the run, you
can start with verbose = 2, which runs fast, then pause, increase verbose to 3, and continue to
generate more informative output.

If you hit the stop button, the execution stops and cannot be resumed.  You will, however, be shown
the data plot up to that time.  The program will also stop and show you the results plot when the
nominal time reaches the selected end time (t1).  As noted above, in order to change parameters the
program must be stopped, not merely paused.  At any time when the program is not running, you can
press the save out button to save the current plot to a file for future viewing or other use.
Depending on the setting of the save options, other data may also be saved to a file.
    
Values of verbose less than or equal to 2 create only a small amount of output, and send it to the
status window on the control panel.  Values greater than 2 create increasing large amounts of
output, and send it to a full-sized terminal window, which can better handle it, and which also
allows it to be saved to a text file.  These outputs are meant for debugging or for a more detailed
look into how the internal variables are changing.  These outputs significantly slow the
calculation.
)
		)->pack;

    $about->Show();
}

sub OnLicense {
    # Construct the DialogBox
    my $about = $mw->DialogBox(
		   -title=>"About",
		   -buttons=>["OK"]
		   );

    # Now we need to add a Label widget so we can show some text.  The
    # DialogBox is essentially an empty frame with no widgets in it.
    # You can images, buttons, text widgets, listboxes, etc.
    $about->add('Label',
		-anchor=>'w',
		-justify=>'left',
		-text=>qq(
RHexCast3D 0.01
Copyright (C) 2019 Rich Miller <rich\@ski.org>

This program is part of RHex. RHex is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software Foundation, either
version 3 of the License, or (at your option) any later version.

RHex is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License along with RHex.  If not, see
<https://www.gnu.org/licenses/>.
)
		)->pack;

    $about->Show();
}


# Show the Help->About Dialog Box
sub OnRod {
    # Construct the DialogBox
    my $params = $mw->DialogBox(
		   -title=>"Line, Leader, Tippet & Fly Params",
		   -buttons=>["OK"]
		   );

    # Now we need to add a Label widget so we can show some text.  The
    # DialogBox is essentially an empty frame with no widgets in it.
    # You can images, buttons, text widgets, listboxes, etc.
    $params->add('Label',
		-anchor=>'w',
		-justify=>'left',
		-text=>qq{
ROD:

numberOfSegments - The number of straight segments into which the rod is divided for the purpose of
	calculation. The integrator follows the time evolution of the junctions of these segments.  Must
	be an integer >= 1. Larger numbers of segments mean a smoother depiction of the rod motion, but
	come at the cost of longer calculation times.  These times vary with the 3rd power of the total
	number of segments (rod plus line), so, for example, 20 total segments will take roughly 64 times
	as long to compute as 5 segments. Typical range for the rod is [5,10].  It is often a good strategy
	to test various parameter settings with a small number of total segments, and when you have
	approximately what you want, go to 15 or even 20 or more for the final picture.

segmentsExponent - Values different from 1 cause the lengths of the segments to vary as you go from the
	rod butt toward the tip.  The exponent must be positive.  Values less than 1 make the segments near
	the rod butt longer than those near the tip.  This is usually what you want, since varying the
	segment lengths but not the number does not change computational cost (that is, time), and it is
	generally desirable to have more detail near the tip.  Typical range is [0.5,2].

rodLength - The total length of the rod in feet, including the handle.  It must be positive. Typical
	range is [6,14].

actionLength - The length in feet from the top of the handle to the tip. It must be positive. Typical
	range is [5.25,12.5].

numberOfSections - Used for adjusting rod stiffness near the ferrules.  Typical range is [1,6].

crossSectionGeometry - One of hex, square, or round.

buttDiameter - In inches.  Used only when no rod file is specified.  Must be non-negative. Typical range
	is [0.500,0.300].

tipDiameter - In inches.  Used only when no rod file is specified.  Must be non-negative. Typical range
	is [0.060,0.100].

fiberGradient - In units of 1/inches.  Bamboo is modelled as getting its strength, elasticity and damping
	from the power fibers only.  These are more dense near the outer surface (enamel) of the bamboo stalk
	(culm).  This parameter lets you specify how quickly the density drops.
	
maxWallThickness - For hollow core rods.  Not yet implemented here.

ferruleKsMultiplier - For multi-segment rods, there is an increase of stiffness locally at and near the
	ferrules because of the additional materials needed to form the joint.  Typical range is [1,2].
	
varnish and Guides Multiplier - In units of ounces per square inch.  The varnish and line guides add a
	little mass to the rod, typically without adding significant stiffness.  This parameter lets you
	adjust the calculation to take this into account.  Typically a small number, the weight of a 1 square
	inch layer of varnish that is a few thousandths of an inch thick, so typically perhaps 0.001.

elasticModulus - In pounds per square inch.  Higher for bamboo than for most woods.  Numbers in the
	literature are in the range [2e6,6e6], that is 2-6 million.
	
dampingModulusStretch - In pounds per square inch.  In solid materials, during deformation, there is an
	internel friction due to material bits sliding past one another.  This converts coherent kinetic
	energy to heat, which is lost to the rod motion, tending to slow down vibrations and larger scale
	movements.  It is hard to find numbers in the literature.  However, this number has a great effect
	on the stability of the numerical integration.  Empirically, values much different from 100 slow the
	calculation down hugely!  It would be good to understand this better, and possibly improve the code.

dampingModulusBend - In pounds per square inch.  Like the case of material stretching, but the way rod
	fibers slide along one another in bending means there should be considerations in addition to those
	of simple viscous deformation.  Part of this is accounted for by using the second moment of
	the cross-section in bending and simply the cross-sectional area itself for stretching (just as
	when calculating elastic force in bending and in tension/compression), but it is possible that the
	modulus itself should also be different.  Empirically, values near 1 work here.
	
NOTE that the best way to estimate these moduli for real rods is to hold them vertically with no line
	and set them in simple oscillatory motion.  Adjust the elastic modulus until the simulation
	oscillation frequency matches that of the real rod.  Adjust the damping moduli so that the reduction
	in oscillation amplitude matches the real thing.  You may actually have to tweak both alternately
	to home in on the correct final answer.
}
		)->pack;

    $params->Show();
}

	
sub OnAmbientEtc {
    # Construct the DialogBox
    my $params = $mw->DialogBox(
		   -title=>"Ambient & Stream Params",
		   -buttons=>["OK"]
		   );

    # Now we need to add a Label widget so we can show some text.  The
    # DialogBox is essentially an empty frame with no widgets in it.
    # You can images, buttons, text widgets, listboxes, etc.
    $params->add('Label',
		-anchor=>'w',
		-justify=>'left',
		-text=>qq{
AMBIENT

gravity - Gravity in G\'s, must be must be non-negative. Typical value is 1.

dragSpecsNormal - Three comma separated numbers that, together with the relative fluid velocity
	determine the drag of a fluid perpendicular to a nominally straight line segment.  The specs must
	be a string of the form MULT,POWER,MIN where the first two are greater than zero and the last is
	greater than or equal to zero.  Remarkably, these numbers do not much depend on the type of fluid
	(in our case, air or water).  Experimentally measured values are 11,-0.74,1.2, and you should only
	change them with considerable circumspection.

dragSpecsAxial -  Again three comma separated numbers.  Analogous to the normal specs described above,
	but accounting for drag forces parallel to the orientation of a line segment. The theoretical
	support for this drag model is much less convincing than in the normal case.  You can try
	11,-0.74,0.1.  The last value should be much less than the equivalent value in the normal spec,
	but what its actual value should be is not that clear.  However, the situation is largely saved
	by that fact that whatever the correct axial drag is, it is always a much smaller number than the
	normal drag, and so should not cause major errors in the simulations.

INITIAL ROD and LINE CONFIGURATION

rodTotalTheta - In degrees.  Used when initial configurations is not specified in the rod file. Total curve
	angle from rod handle to rod tip.  Convex away from the direction of the fly line.

rodTipToFlyAngle - Sets the combined line angle in degrees in the vertical plane at the start of the integration.
	Must be in the range (-180,180).  0 is straight up, -90 is horizontal to the left.
	
lineCurvature - In units of 1\/feet. Equals 1 divided by the radius of curvature.  With the direction from
	the rod tip to the fly set as above, non-zero line curvature sets the line to bow along a vertical
	 circular arc.  Negative curvatures are concave up, which is what you would have under the influence of
	 gravity with a held fly.  The absolute value of the curvature must be no greater than 2\/totalLength.

INITIAL FLY HOLDING

releaseDelay - In seconds. The time interval during which the fly is held in its original position while the
	rod handle begins to move, thereby bending the rod and tightening the line.  Corresponds to the situation
	for a water loaded cast, but perhaps even more useful as a way of starting a cast without the need for a
	preliminary back cast.  The power stroke for a typical forward cast with a single-hand rod is only about
	0.5 seconds.  Thus a hold in the range of [0.15,0.200] seconds is frequently appropriate.

releaseDuration - In seconds.  To avoid a sudden jolt when the fly is released, corresponds to the short time
	when the fly is slipping through the fingers during release.  A number of the order of 0.015 works well.
}
		)->pack;

    $params->Show();
}


sub OnHandleMotion {
    # Construct the DialogBox
    my $params = $mw->DialogBox(
		   -title=>"Initial Line Configuration, Manipulation, and Rod Tip Motion Params",
		   -buttons=>["OK"]
		   );

    # Now we need to add a Label widget so we can show some text.  The
    # DialogBox is essentially an empty frame with no widgets in it.
    # You can images, buttons, text widgets, listboxes, etc.
    $params->add('Label',
		-anchor=>'w',
		-justify=>'left',
		-text=>qq{
HANDLE MOTION

NOTE that the handle motion is defined by the location of the top of the handle in space together with the
	3D direction from the butt of the handle to its top, both as functions of time.

powerStartCoords - In inches.  Sets the initial 3D position of the handle top during the power stroke.  Must be
	of the form of three comma separated numbers, X,Y,Z. Typical values are within an arm\'s length of the
	shoulder.  Used as the initial position even if a cast driver is loaded from a file unless an initial
	position is set in the file.
	
The rest of the coordinates below, except drift end time, are only used if the cast is not loaded from a file.

powerEndCoords - In inches.  Same form and restrictions as for the start coordinates. If the start and end
	coordinates are the same, there is no power stroke motion.  This is one way to turn off motion.  The other
	way is to make the power start and drift end times equal (see below).

powerPivotCoords - Same form as the start coordinates.  These coordinates are irrelevant if the handle top track
	is set as a straight line between its start and end.  However if the track is curved (see below), the
	pivot, which you may envision as your shoulder joint, together with the track starting and ending points
	defines a plane.  In the current implementation, the curved	track is constrained to lie in that plane.
	Typical values are the range of positions of the shoulder.

powerMeanCurvature - In units of 1\/inches. Equals 1 divided by the track radius of curvature. Sets the amount of bow
	in the handle top track.  Must have absolute value less than 2 divided by the distance between the track start
	and the track end.  Positive curvature is away from the pivot.  This is the usual case.

powerSkewness - Non-zero values skew the curve of the track toward or away from the starting location, allowing
	tracks that are not segments of a circle.  Positive values have peak curvature later in the motion.
	Typical range is [-0.25,0.25].

powerWristStartAngle - In degrees.  Sets the initial handle direction relative to the line from the pivot.  This
	direction lies in the plane containing the power start and end coords and the pivot.  Typical value is [-40,-10].

powerWristEndAngle - In degrees.  Like the wrist start angle.

powerWristAngleSkewness - Positive values give more relative deflection later.

power Start and End times - In seconds.  If the end time is earlier or the same as the start time, there is no
	power stroke motion.  If the handle motion times are not set explicitly in the file, the motion start time
	is set by this start time and the drift end time.

powerVelocitySkewness - Non-zero causes the velocity of the handle top motion to vary in time. Positive causes
	velocity to peak later.  Typical range is [-0.25,0.25].

driftWristEndAngle - In degrees.  Drift starts with the wrist power end angle.  Drift, which follows the power
	stroke, allows only wrist motion, not handle top motion.

drift Start and End times - In seconds.  If the end time is earlier or the same as the start time, there is no
	drift motion.  If the handle motion times are not set explicitly in the file, the motion start time
	is set by the power start time and this end time.

showTrackPlot - If checked, causes the drawing, before the integration starts, of a rotatable 3D plot showing the
	handle track.  You can see the same information at the end of the integration by looking at the handle
	positions in the full plot, but it is sometimes helpful to see an  early, uncluttered version.
}
		)->pack;

    $params->Show();
}


sub OnIntegEtc {
    # Construct the DialogBox
    my $params = $mw->DialogBox(
		   -title=>"Integration, Plotting, and Saving Params",
		   -buttons=>["OK"]
		   );

    # Now we need to add a Label widget so we can show some text.  The
    # DialogBox is essentially an empty frame with no widgets in it.
    # You can images, buttons, text widgets, listboxes, etc.
    $params->add('Label',
		-anchor=>'w',
		-justify=>'left',
		-text=>qq{
INTEGRATION, PLOTTING AND SAVING

t0 - The notional time in seconds when the compution begins.  Must be non-negative, but this entails no loss of
	generality. Usually set to 0.

t1 - The notional time when the computation ends.  Must larger than t0. Usually less than 60 seconds.

dt0 - The initial computational timestep.  Must be positive.  Since the integrator has the ability to adjust the
	timestep as it goes along, this setting is not very important.  However, finding an appropriate value saves
	some computation time as the integrator begins its work. Typical range is [1e-4,1e-7].

plotDt - In seconds. This is an important parameter in terms of the utility of the final 3D plots. It sets the
	(uniform) interval at which a sequence of segment junction coordinates are reported by the integrator.  The
	integrator guarantees that the reported position values at these times have the desired degree of accuracy.
	Must be positive.  There is a modest computational cost for more frequent reporting, but it is not great.
	The bigger problem is that a short plotDt interval clutters up the final 3D graphic.  For the purpose of
	understanding the details of a swing, an interval of 1 second is usually a good choice, since adjacent traces
	are far enough apart that they don\'t obscure one another, and also since counting traces is then the same as
	counting seconds.  However, sometimes you want to see more detail, and have reporting occur earlier.  This
	happens mainly if for some reason the calculation has trouble getting started, and you want to catch the
	integrator\'s earliest efforts. Typical range is [0.1,1].

Note, however, that if you have a plot that is too cluttered, you can use the save results button (in particular,
	the save as text option).  This writes the results to a file.  Later you can run the RHexReplot3D program to
	read this file, and replot it in less dense and more restricted time manner.  Of course, replot can only work
	with what you have given it, so if the initially reported data is too sparse, you are stuck.

integrationStepperChoice - This menu allows you to choose from among 11 different stepper algorithms.  Some work
	better (are faster and more reliable) in some situations, and others work better in other situations.  However,
	for our purposes, the first choice, msbdf_j, seems to give the best results.

saveOptions - When you hit the Save Out button if the \"plot\" box is checked (colored red), an .eps picture file
	of the results will be created and saved.  This picture can be attached to an email or viewed in any of a
	number of programs.  In particular, on the mac, it can be opened in Preview.  However, this picture is
	\"static\".  What you see is what you get.  You can only resize it.  This is unlike the \"live\" plot that is
	shown when a RHexCast3D run is paused or completes, which can be rotated any which way using the mouse.  On
	the other hand, if you check the \"data\" box, a text file is created.  That file can be opened in any text
	editor, and you can read the actual coordinate numbers that define the traces, as well as the parameter
	settings that gave rise to those traces.  In addition, that file can be opened in RHexReplot3D, and from there
	replotted in live, rotatable form.
}
		)->pack;

    $params->Show();
}




#evaluates code in the entry text pane
sub OnEval{
}

__END__


=head1 NAME

RHexCast3D - A PERL program that simulates the motion of a rod and multi-component fly line (line
proper, leader, tippet and fly) during a cast under the influence of gravity, air friction and
internal stresses.  The cast is driven by a user defined motion of the rod handle.  User definition
also sets the initial configuration of the rod and line.

=head1 SYNOPSIS

Enter perl RHexCast3D.pl in a terminal window, or double-click on the shell script RHexCast3D.sh
in the finder window, or run the stand-alone executable RHexCast3D if it is available.
  
=head1 DESCRIPTION

The results of the calculation are displayed as constant-time-interval colored traces on a 3D plot
that can be rotated at will by the motion of the cursor.  The earliest traces are shown in green and
the latest in red, with the intermediate traces shown as brownish shades that are the combination of
green and red in appropriate proportion.  Open circles, solid circles, diamonds and squares mark the
locations of the rod tip, line-leader and leader-tippet junctions, and the fly.
    
The interactive control panel allows the setting of parameters that control the details of the line
make-up, the water flow, the initial line location, the rod tip movement, the stripping starting
time and velocity, and details of the integration and plotting.  In addition, the panel allows for
the selection of a parameter preference file, which presets all the parameters to a
previously saved condition, as well as the selection of files that define specific fly-lines and
leaders, and of another that loads a textual description of a rod-tip motion.  Use of the line, leader
and motion files allows the simulation of any fly line with any motion, not just those constructable
using the parameters.

More information, including a detailed description of the parameters and their allow values, is
available from the help menu located in the upper left corner of the control panel.

The code in this file builds and deploys the control panel, whose buttons invoke functions in RCast3D.pm
that set up and run a Gnu Scientific Library ODE solver.  The solver is called from RUtils::DiffEq via an
XS interface. The solver integrates Hamilton's equations, calling a function in RHexHamilton3D.pm that provides
time derivatives of the dynamical variables at configurations set by the solver.  The GSL solver can invoke
any of a number of different stepping algorithms.  Some of these require knowledge of a Jacobian matrix.
This is provided numerically by the numjac function in RUtils::NumJac.

RUtils::Print and RUtils::Plot provide quick and simple printing and plotting capabilities, while RCommon.pm
provides very specialized utility functions that are used by both the Swing and Cast programs.  RCommonPlot3D.pm
does the plotting for all the programs of the RHex project.  All of the modules mentioned have their own POD
documentation.

=head1 A USEFUL NOTE

Every time a simulation run goes to completion, or is paused or stopped by user action, plot is drawn
that depicts the results up to that point.  Subsequent continuation or starting of a new run, when they
stop, produces another plot.  And so on.  These plots persist, so quite a few of them can accumulate.
You can manually go and close each with its window's close button, but that can become tedious.  A much
quicker procedure is to first save your parameters, and then simply close the Terminal window that appeared
when this program was launched.  That will cause all the plots to disappear.  Then simply relaunch this
program.  Because you have saved the parameters, the new launch will start where the old one left off.

=head1 AUTHOR

Rich Miller, E<lt>rich@ski.orgE<gt>

=head1 COPYRIGHT AND LICENSE

RHex - 3D dyanmic simulation of fly casting and swinging.

Copyright (C) 2019 Rich Miller

This file is part of RHex.

RHex is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

RHex is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with RHex.  If not, see <https://www.gnu.org/licenses/>.

=cut

