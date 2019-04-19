#!/usr/bin/perl -w

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
use Carp;

use RCommon qw (DEBUG $program $exeDir $verbose $debugVerbose %runControl);

my $nargs;

BEGIN {
    $nargs = @ARGV;
    if ($nargs>1){die "\n$0: Usage:RHexReplot[.pl] [settingsFile]\n"}
    
    chomp(my $exeName = `echo $0`);
    # Gets rid of the trailing newline with which shell commands finish.
    print "Running $exeName @ARGV\n";
    
    chomp($exeDir  = `dirname $0`);
    #print "exeDir = $exeDir\n";
    chdir "$exeDir";  # See perldoc -f chdir
    #`cd $exeDir`;   # This doesn't work, but the perl function chdir does!
    chomp($exeDir = `pwd`);  # Force full pathname.
    print "Working in $exeDir\n";
	
	$program = "RCast3D";
}

# Put the launch directory on the perl path. This needs to be here, outside and below the BEGIN block.
use lib ($exeDir);

use RCommonInterface;
use RCast3D qw ($rps);

$updateFieldStates	= \&UpdateFieldStates;

# --------------------------------

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

use Config::General;
use Switch;     # WARNING: switch fails following an unrelated double-quoted string literal containing a non-backslashed forward slash.  This despite documentation to the contrary.
use File::Basename;

use RUtils::Print;
use RCommonPlot3D qw ( $gnuplot );

# See if gnuplot and gnuplot_x11 are installed.  The latter is an auxilliary executable to manage the plots displayed in the X11 windows.  It is not necessary for the drawing of the control panel or the creation of the .eps files (see INSTALL in the Gnuplot distribution):
chomp($gnuplot = `which gnuplot`);
if (!$gnuplot){
    print "Cannot find a system gnuplot, will try to use a local copy.\n";
    $gnuplot = $exeDir."/gnuplot";
    if (-e $gnuplot and -x $gnuplot) {
		my $gnuplot_x11 = $exeDir."/gnuplot_x11";
		if (-e $gnuplot_x11 and -x $gnuplot_x11) {
			$ENV{GNUPLOT_DRIVER_DIR} = "$exeDir";
        	print "Using gnuplot and gnuplot_x11 found in $exeDir.\n";
			} else {
				croak "ERROR: Unable to find a local gnuplot_x11 on the system, cannot proceed.\n";
			}
    } else {
        croak "ERROR: Unable to find an executable gnuplot on the system, cannot proceed.\n";
    }
}

#use Tie::Watch;
    # Keep this in mind for general use.  However, for widgets, one can usually use the -validate and -validatecommand options to do what we want.
    # For redirecting STOUT when $verbose changes.  Maybe we can do this directly in TK.
#use Try::Tiny;  # Try to keep our validation from going away. DOESN'T WORK.

my $defaultSettingsFile = $rps->{file}{settings};
# Save a copy from startup values in RHexCastPkg.  During running of this program the value may be overwritten.


# Main Window
my $mw = new MainWindow;
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
my $files_fr     = $mw->Labelframe(-text=>"Files")->pack(qw/-side top -fill both -expand 1/);

my $params_fr       = $mw->Frame->pack(qw/-side top -fill both -expand 1/);
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

my $status_rot = $status_scrl->Subwidget("rotext");  # Needs to be lowercase!(?)


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
    $files_fr->Button(-text=>'Select',-command=>sub{OnCastSelect(),-height=>'0.5'})->grid(-row=>3,-column=>1);
    $files_fr->Button(-text=>'None',-command=>sub{OnCastNone(),-height=>'0.5'})->grid(-row=>3,-column=>2);


# Set up the rod frame contents -----
my @rodFields;

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
my @lineFields;

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
    $lineFields[0] = $line_fr->LabEntry(-textvariable=>\$rps->{line}{nomDiameterIn},-label=>'nomDiam(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>9,-column=>0,-sticky=>'e');
    $lineFields[1] = $line_fr->LabEntry(-textvariable=>\$rps->{line}{coreDiameterIn},-label=>'coreDiam(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>10,-column=>0,-sticky=>'e');
    $line_fr->LabEntry(-textvariable=>\$rps->{line}{coreElasticModulusPSI},-label=>'coreElasticMod(psi)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>11,-column=>0,-sticky=>'e');
    $line_fr->LabEntry(-textvariable=>\$rps->{line}{dampingModulusPSI},-label=>'dampingMod(psi)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>12,-column=>0,-sticky=>'e');

# Set up the tippet_fly frame contents -----
my @leaderFields;

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
    $ambient_fr->LabEntry(-textvariable=>\$rps->{line}{angle0Deg},-label=>'lineAngle0(deg)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>5,-column=>0,-sticky=>'e');
    $ambient_fr->LabEntry(-textvariable=>\$rps->{line}{curve0InvFt},-label=>'lineCurve0(1/ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>6,-column=>0,-sticky=>'e');
    $ambient_fr->Label(-text=>'',-width=>8)->grid(-row=>7,-column=>0,-sticky=>'e');

    $ambient_fr->LabEntry(-textvariable=>\$rps->{integration}{releaseDelay},-label=>'releaseDelay',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>8,-column=>0,-sticky=>'e');
    $ambient_fr->LabEntry(-textvariable=>\$rps->{integration}{releaseDuration},-label=>'releaseDuration',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>9,-column=>0,-sticky=>'e');


# Set up the driver frame contents ------
my @driverFields;

    $driverFields[0] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{startCoordsFt},-label=>'hndlTopStart(ft)',-labelPack=>[qw/-side left/],-width=>11)->grid(-row=>0,-column=>0,-sticky=>'e');
    $driverFields[1] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{endCoordsFt},-label=>'hndlTopEnd(ft)',-labelPack=>[qw/-side left/],-width=>11)->grid(-row=>1,-column=>0,-sticky=>'e');
    $driverFields[2] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{pivotCoordsFt},-label=>'hndlPivotft)',-labelPack=>[qw/-side left/],-width=>11)->grid(-row=>2,-column=>0,-sticky=>'e');
    $driverFields[3] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{dirStartCoordsFt},-label=>'hndlDirStart(ft)',-labelPack=>[qw/-side left/],-width=>11)->grid(-row=>3,-column=>0,-sticky=>'e');
    $driverFields[4] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{dirEndCoordsFt},-label=>'hndlDirEnd(ft)',-labelPack=>[qw/-side left/],-width=>11)->grid(-row=>4,-column=>0,-sticky=>'e');
    $driverFields[5] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{trackCurvatureInvFt},-label=>'trackMeanCurv(1/ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>5,-column=>0,-sticky=>'e');
	$driverFields[6] =  $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{trackSkewness},-label=>'trackSkewness',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>6,-column=>0,-sticky=>'e');
    $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{startTime},-label=>'motionStartTime(sec)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>7,-column=>0,-sticky=>'e');
    $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{endTime},-label=>'motionEndTime(sec)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>8,-column=>0,-sticky=>'e');
    $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{velocitySkewness},-label=>'motionVelSkewness',-labelPack=>[qw/-side left/],-width=>9)->grid(-row=>9,-column=>0,-sticky=>'e');
    $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{showTrackPlot},-label=>'showTrackPlot',-labelPack=>[qw/-side left/],-width=>10)->grid(-row=>10,-column=>0,-sticky=>'e');




=begin comment

    $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{frameRate},-label=>'frameRate(hz)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>4,-column=>0,-sticky=>'e');
    $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{adjustEnable},-label=>'adjustEnable',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>5,-column=>0,-sticky=>'e');

    $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{scale},-label=>'scale',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>6,-column=>0,-sticky=>'e');
    $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{rotate},-label=>'rotate(rad)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>7,-column=>0,-sticky=>'e');
    $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{wristTheta},-label=>'wristTheta(rad)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>8,-column=>0,-sticky=>'e');
    $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{relRadius},-label=>'relativeROC',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>9,-column=>0,-sticky=>'e');
    $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{driveAccelFrames},-label=>'drive,accel(fr)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>10,-column=>0,-sticky=>'e');
    $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{delayDriftFrames},-label=>'delay,drift(fr)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>11,-column=>0,-sticky=>'e');
    $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{driveDriftTheta},-label=>'drive,drift(rad)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>12,-column=>0,-sticky=>'e');
$driver_fr->LabEntry(-textvariable=>\$rps->{driver}{boxcarFrames},-label=>'boxcar(fr)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>13,-column=>0,-sticky=>'e');
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


    my $debugVerboseField;
    if (DEBUG){
        $debugVerboseField = $int_fr->LabEntry(-textvariable=>\$rps->{integration}{debugVerbose},-label=>'debugVerbose',-labelPack=>[qw/-side left/],-width=>3)->grid(-row=>9,-column=>0,-sticky=>'e');
    } else {
        $debugVerbose = 3;  # The only thing that makes sense in this situation.
    }
    my $verboseField = $int_fr->LabEntry(-textvariable=>\$rps->{integration}{verbose},-label=>'verbose',-validate=>'key',-validatecommand=>\&OnVerbose,-invalidcommand=>undef,-labelPack=>[qw/-side left/],-width=>3)->grid(-row=>10,-column=>0,-sticky=>'e');


# Set up the rest of the run frame contents ---------
my $quit_btn  = $run_fr->Button(-text=>'Quit',-command=>sub{OnExit()}
        )->grid(-row=>3,-column=>0);
$run_fr->Button(-text=>'Save Settings',-command=>sub{OnSaveSettings()}
        )->grid(-row=>3,-column=>1);
my $runPauseCont_btn  = $run_fr->Button(-text=>'RUN',-command=>sub{OnRunPauseCont()}
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
my $currentVerbose = $rps->{integration}{verbose};
$rps->{integration}{verbose} = $currentVerbose;

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



# ==============
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
	 ['command', 'About', -command=>[\&OnAbout]]
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
		   -title=>"About RHexCast",
		   -buttons=>["OK"]
		   );

    # Now we need to add a Label widget so we can show some text.  The
    # DialogBox is essentially an empty frame with no widgets in it.
    # You can images, buttons, text widgets, listboxes, etc.
    $about->add('Label',
		-anchor=>'w',
		-justify=>'left',
		-text=>qq(
RHexCast 1.1, by Rich Miller, 2015

A graphical interface to a program that simulates the motion of a bamboo hex rod,
line, leader, and fly during a cast.  The user sets parameters which specify the
physical and dimensional properties of the above components as well as the time-motion
of the rod handle, which is the ultimate driver of the cast.

The program outputs datafiles and cartoon images that show successive stop-action
frames of the components.  Parameter settings may be saved and retrieved for easy
project management.

See the file RHexCast - Help for more detail.
)
		)->pack;

    $about->Show();
}


#evaluates code in the entry text pane
sub OnEval{
}

__END__

=head1 NAME

RHexCast3D - A PERL program that simulates the motion of a multi-component fly rod and line (rod,
line proper, leader, tippet and fly) during a cast under the influence of gravity, fluid friction,
internal stresses, and a user defined initial configuration and rod handle motion. RHexSwing3D is
one of the two main programs of the RHex Project.


=head1 SYNOPSIS

Enter perl RHexCast3D.pl in a terminal window, or double-click on the shell script RHexCast3D.sh
in the finder window, or run the stand-alone executable RHexCast3D if it is available.
  
=head1 DESCRIPTION

??? The results of the calculation are displayed as constant-time-interval colored traces on a 3D plot
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
provides very specialized utility functions that are used by both the Swing and Cast programs.
RCommonPlot3D.pm does the plotting for all the programs of the RHex project.  All of the modules mentioned
have their own POD documentation.

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

sub OnRodSelect {
    my $FSref = $mw->FileSelect(    -filter=>'(*.txt)|(*.xls)');
    $FSref->geometry('700x500');    
    my $filename = $FSref->Show;
    if ($filename){
        $rps->{file}{rod} = $filename;
    }
}

sub OnRodNone {
    $rps->{file}{rod} = '';
}

