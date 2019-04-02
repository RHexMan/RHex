#!/usr/bin/perl -w

#############################################################################
## Name:			RHexSwing3D.pm
## Purpose:			Graphical user interface to RSwing3D
## Author:			Rich Miller
## Modified by:
## Created:			2019/2/18
## Modified:
## RCS-ID:
## Copyright:		(c) 2019 Rich Miller
## License:			This program is free software; you can redistribute it and/or
##					modify it under the same terms as Perl itself
#############################################################################


## If run with one arg, it is taken to be the .prefs file.  Generally, when loading, file navigation will start with the exe dir, and when saving, with the directory that holds the current settings file if there is one, otherwise with the exe dir.  That will encourage outputs associated with "related" settings to settle naturally in one folder.

# The code is almost all boilerplate Tk. https://metacpan.org/pod/distribution/Tk/pod/UserGuide.pod


my $nargs;
my $exeDir;

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
}

use lib ($exeDir);   # This needs to be here, outside and below the BEGIN block.

use RSwing3D;    # For verbose, right away.

# --------------------------------

use warnings;
use strict;

use Carp;

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
use File::Spec::Functions qw ( rel2abs abs2rel splitpath );

use RUtils::Print;

use RCommonPlot3D qw ( $gnuplot );


# See if gnuplot is installed:
chomp($gnuplot = `which gnuplot`);
if (!$gnuplot){
    print "Cannot find a system gnuplot, will try to use a local copy.\n";
    $gnuplot = $exeDir."/rgnuplot";
    if (-e $gnuplot and -x $gnuplot) {
        print "Using $gnuplot.\n";
    } else {
        croak "ERROR: Unable to find an executable gnuplot on the system, cannot proceed.\n";
    }
}


#use Tie::Watch;
    # Keep this in mind for general use.  However, for widgets, one can usually use the -validate and -validatecommand options to do what we want.
    # For redirecting STOUT when $verbose changes.  Maybe we can do this directly in TK.
#use Try::Tiny;  # Try to keep our validation from going away. DOESN'T WORK.

# Widget Construction ==================================

my $rps = \%rSwingRunParams;

my $defaultSettingsFile = $rps->{file}{settings};
# Save a copy from startup values in RSwing.  During running of this program the value may be overwritten.


# Main Window
my $mw = new MainWindow;
$mw->geometry('1100x700+100+0');
$mw->resizable(0,0);
#$mw->Tk::Error("error message", location ...);
#$mw->Tk::Error("error message");
#$mw->Tk::ErrorDialog(-appendtraceback => 0);

# https://perldoc.perl.org/perlref.html
$rSwingRunControl{callerUpdate}         = sub {$mw->update};
$rSwingRunControl{callerStop}           = sub {OnStop()};
$rSwingRunControl{callerRunState}       = 0;   # 1 keep running, -1 pause, 0 stop.
#$rSwingRunControl{callerChangeVerbose}  = sub {ChangeVerbose()};
#$rSwingRunControl{callerChangeVerbose}  = \&ChangeVerbose;
#$rSwingRunControl{callerChangeVerbose}  = sub {my $v = shift; return ChangeVerbose($v)};
# The problem was here.  This works.
$rSwingRunControl{callerChangeVerbose}  = \&ChangeVerbose; # This is the right way.
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
my $files_fr    = $mw->Labelframe(-text=>"Files")->pack(qw/-side top -fill both -expand 1/);

my $params_fr   = $mw->Frame->pack(qw/-side top -fill both -expand 1/);
my $line_fr     = $params_fr->Labelframe(-text=>"Line & Leader")->pack(qw/-side left -fill both -expand 1/);
my $tippet_fr   = $params_fr->Labelframe(-text=>"Tippet, Fly & Ambient")->pack(qw/-side left -fill both -expand 1/);
my $stream_fr   = $params_fr->Labelframe(-text=>"Stream Specification &\nInitial Line Configuration")->pack(qw/-side left -fill both -expand 1/);
my $driver_fr   = $params_fr->Labelframe(-text=>"Line Manipulation\n& Rod Tip Motion")->pack(qw/-side left -fill both -expand 1/);
my $int_fr      = $params_fr->Labelframe(-text=>"Integration, Etc")->pack(qw/-side left -fill both -expand 1/);

my $run_fr      = $mw->Labelframe(-text=>"Execution")->pack(qw/-side bottom -fill both -expand 1/);

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

    $files_fr->LabEntry(-state=>'readonly',-relief=>'groove',-textvariable=>\$rps->{file}{line},-label=>'Line',-labelPack=>[qw/-side left/],-width=>100)->grid(-row=>1,-column=>0,-sticky=>'e');
    $files_fr->Button(-text=>'Select',-command=>sub{OnLineSelect(),-height=>'0.5'})->grid(-row=>1,-column=>1);
    $files_fr->Button(-text=>'None',-command=>sub{OnLineNone(),-height=>'0.5'})->grid(-row=>1,-column=>2);

    $files_fr->LabEntry(-state=>'readonly',-relief=>'groove',-textvariable=>\$rps->{file}{leader},-label=>'Leader',-labelPack=>[qw/-side left/],-width=>100)->grid(-row=>2,-column=>0,-sticky=>'e');
    $files_fr->Button(-text=>'Select',-command=>sub{OnLeaderSelect(),-height=>'0.5'})->grid(-row=>2,-column=>1);
    $files_fr->Button(-text=>'None',-command=>sub{OnLeaderNone(),-height=>'0.5'})->grid(-row=>2,-column=>2);

    $files_fr->LabEntry(-state=>'readonly',-relief=>'groove',-textvariable=>\$rps->{file}{driver},-label=>'RodTipMotion',-labelPack=>[qw/-side left/],-width=>100)->grid(-row=>3,-column=>0,-sticky=>'e');
    $files_fr->Button(-text=>'Select',-command=>sub{OnDriverSelect(),-height=>'0.5'})->grid(-row=>3,-column=>1);
    $files_fr->Button(-text=>'None',-command=>sub{OnDriverNone(),-height=>'0.5'})->grid(-row=>3,-column=>2);


# Set up the line_leader frame contents -----

my @lineFields;
my @leaderFields;

    $line_fr->LabEntry(-textvariable=>\$rps->{line}{activeLenFt},-label=>'totalLengthRodTipToFly(ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>0,-column=>0,-sticky=>'e');
    $line_fr->LabEntry(-textvariable=>\$rps->{line}{nomWtGrsPerFt},-label=>'lineNominalWt(gr/ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>1,-column=>0,-sticky=>'e');
    $lineFields[0] = $line_fr->LabEntry(-textvariable=>\$rps->{line}{estimatedDensity},-label=>'lineEstDensity',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>2,-column=>0,-sticky=>'e');
    $lineFields[1] = $line_fr->LabEntry(-textvariable=>\$rps->{line}{nomDiameterIn},-label=>'lineNomDiameter(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>3,-column=>0,-sticky=>'e');
    $lineFields[2] = $line_fr->LabEntry(-textvariable=>\$rps->{line}{coreDiameterIn},-label=>'lineCoreDiameter(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>4,-column=>0,-sticky=>'e');
    $line_fr->LabEntry(-textvariable=>\$rps->{line}{coreElasticModulusPSI},-label=>'lineCoreElasticModulus(PSI)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>5,-column=>0,-sticky=>'e');
    $line_fr->LabEntry(-textvariable=>\$rps->{line}{dampingModulusPSI},-label=>'lineDampingModulus(PSI)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>6,-column=>0,-sticky=>'e');
    my @aLeaderItems = ("leader - level","leader - 7ft 5x","leader - 10ft 3x");
    $leaderFields[0] = $line_fr->Optionmenu(-options=>\@aLeaderItems,-variable=>\$rps->{leader}{idx},-textvariable=>\$rps->{leader}{text},-relief=>'sunken')->grid(-row=>7,-column=>0,-sticky=>'e');
    $leaderFields[1] = $line_fr->LabEntry(-textvariable=>\$rps->{leader}{lenFt},-label=>'leaderLen(ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>8,-column=>0,-sticky=>'e');
    $leaderFields[2] = $line_fr->LabEntry(-textvariable=>\$rps->{leader}{wtGrsPerFt},-label=>'leaderWt(gr/ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>9,-column=>0,-sticky=>'e');
    $leaderFields[3] = $line_fr->LabEntry(-textvariable=>\$rps->{leader}{diamIn},-label=>'leaderDiam(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>10,-column=>0,-sticky=>'e');
    $leaderFields[4] = $line_fr->LabEntry(-textvariable=>\$rps->{leader}{coreDiamIn},-label=>'leaderCoreDiam(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>11,-column=>0,-sticky=>'e');


# Set up the tippet, fly and ambient frame contents -----
    my @aTippetItems = ("tippet - mono","tippet - fluoro");
    $tippet_fr->Optionmenu(-options=>\@aTippetItems,-variable=>\$rps->{tippet}{idx},-textvariable=>\$rps->{line}{text},-relief=>'sunken')->grid(-row=>0,-column=>0,-sticky=>'e');
    $tippet_fr->LabEntry(-textvariable=>\$rps->{tippet}{lenFt},-label=>'tippetLen(ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>1,-column=>0,-sticky=>'e');
    $tippet_fr->LabEntry(-textvariable=>\$rps->{tippet}{diamIn},-label=>'tippetDiam(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>2,-column=>0,-sticky=>'e');
    $tippet_fr->LabEntry(-textvariable=>\$rps->{fly}{wtGr},-label=>'flyWeight(gr)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>3,-column=>0,-sticky=>'e');
    $tippet_fr->LabEntry(-textvariable=>\$rps->{fly}{nomDiamIn},-label=>'flyNomDragDiam(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>4,-column=>0,-sticky=>'e');
    $tippet_fr->LabEntry(-textvariable=>\$rps->{fly}{nomLenIn},-label=>'flyNomDragLen(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>5,-column=>0,-sticky=>'e');
    $tippet_fr->LabEntry(-textvariable=>\$rps->{fly}{nomDispVolIn3},-label=>'flyNomDispacement(in3)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>6,-column=>0,-sticky=>'e');
    $tippet_fr->LabEntry(-textvariable=>\$rps->{ambient}{gravity},-label=>'gravity',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>7,-column=>0,-sticky=>'e');
    $tippet_fr->LabEntry(-textvariable=>\$rps->{ambient}{dragSpecsNormal},-label=>'dragSpecsNormal',-labelPack=>[qw/-side left/],-width=>12)->grid(-row=>8,-column=>0,-sticky=>'e');
    $tippet_fr->LabEntry(-textvariable=>\$rps->{ambient}{dragSpecsAxial},-label=>'dragSpecsAxial',-labelPack=>[qw/-side left/],-width=>12)->grid(-row=>9,-column=>0,-sticky=>'e');


# Set up the stream and starting configuration frame contents -----
    $stream_fr->LabEntry(-textvariable=>\$rps->{stream}{surfaceVelFtPerSec},-label=>'surfaceVel(ft/sec)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>0,-column=>0,-sticky=>'e');
    $stream_fr->LabEntry(-textvariable=>\$rps->{stream}{surfaceLayerThicknessIn},-label=>'surfLayerThickness(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>1,-column=>0,-sticky=>'e');
    $stream_fr->LabEntry(-textvariable=>\$rps->{stream}{bottomDepthFt},-label=>'bottomDepth(ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>2,-column=>0,-sticky=>'e');
    $stream_fr->LabEntry(-textvariable=>\$rps->{stream}{halfVelThicknessFt},-label=>'halfVelThickness(ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>3,-column=>0,-sticky=>'e');
    my @aProfileItems = ("profile - const","profile - lin","profile - exp");
    $stream_fr->Optionmenu(-options=>\@aProfileItems,-variable=>\$rps->{stream}{profile},-textvariable=>\$rps->{stream}{profileText},-relief=>'sunken')->grid(-row=>4,-column=>0,-sticky=>'e');
    $stream_fr->LabEntry(-textvariable=>\$rps->{stream}{horizHalfWidthFt},-label=>'horizHalfWidth(ft)',-labelPack=>[qw/-side left/],-width=>12)->grid(-row=>5,-column=>0,-sticky=>'e');
    $stream_fr->LabEntry(-textvariable=>\$rps->{stream}{horizExponent},-label=>'horizExponent',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>6,-column=>0,-sticky=>'e');
    $stream_fr->LabEntry(-textvariable=>\$rps->{stream}{showProfile},-label=>'showVelProfile',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>7,-column=>0,-sticky=>'e');
    $stream_fr->LabEntry(-textvariable=>\$rps->{configuration}{crossStreamAngleDeg},-label=>'rodTipToFlyAngle(deg)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>8,-column=>0,-sticky=>'e');
    $stream_fr->LabEntry(-textvariable=>\$rps->{configuration}{curvatureInvFt},-label=>'lineCurvature(1/ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>9,-column=>0,-sticky=>'e');
    $stream_fr->LabEntry(-textvariable=>\$rps->{configuration}{preStretchMult},-label=>'preStretchMult',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>10,-column=>0,-sticky=>'e');
    $stream_fr->LabEntry(-textvariable=>\$rps->{configuration}{tuckHeightFt},-label=>'tuckHeight(ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>11,-column=>0,-sticky=>'e');
    $stream_fr->LabEntry(-textvariable=>\$rps->{configuration}{tuckVelFtPerSec},-label=>'tuckVel(ft/sec)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>12,-column=>0,-sticky=>'e');


# Set up the driver frame contents ------
my @driverFields;

    $driverFields[0] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{laydownIntervalSec},-label=>'laydownInterval(sec)',-labelPack=>[qw/-side left/],-width=>12)->grid(-row=>0,-column=>0,-sticky=>'e');
    $driverFields[1] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{sinkIntervalSec},-label=>'sinkInterval(sec)',-labelPack=>[qw/-side left/],-width=>12)->grid(-row=>1,-column=>0,-sticky=>'e');
    $driverFields[2] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{stripRateFtPerSec},-label=>'stripRate(ft/sec)',-labelPack=>[qw/-side left/],-width=>12)->grid(-row=>2,-column=>0,-sticky=>'e');
    $driverFields[3] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{startCoordsFt},-label=>'tipStartCoords(ft)',-labelPack=>[qw/-side left/],-width=>12)->grid(-row=>3,-column=>0,-sticky=>'e');
    $driverFields[4] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{endCoordsFt},-label=>'tipEndCoords(ft)',-labelPack=>[qw/-side left/],-width=>12)->grid(-row=>4,-column=>0,-sticky=>'e');
    $driverFields[5] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{pivotCoordsFt},-label=>'trackPivotCoords(ft)',-labelPack=>[qw/-side left/],-width=>12)->grid(-row=>5,-column=>0,-sticky=>'e');
    $driverFields[6] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{trackCurvatureInvFt},-label=>'trackMeanCurvature(1/ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>6,-column=>0,-sticky=>'e');
    $driverFields[7] = $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{trackSkewness},-label=>'trackSkewness',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>7,-column=>0,-sticky=>'e');
    $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{startTime},-label=>'motionStartTime(sec)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>8,-column=>0,-sticky=>'e');
    $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{endTime},-label=>'motionEndTime(sec)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>9,-column=>0,-sticky=>'e');
    $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{velocitySkewness},-label=>'motionVelSkewness',-labelPack=>[qw/-side left/],-width=>9)->grid(-row=>10,-column=>0,-sticky=>'e');
    $driver_fr->LabEntry(-textvariable=>\$rps->{driver}{showTrackPlot},-label=>'showTrackPlot',-labelPack=>[qw/-side left/],-width=>10)->grid(-row=>11,-column=>0,-sticky=>'e');



# Set up the integration frame contents -----

    $int_fr->LabEntry(-textvariable=>\$rps->{integration}{numSegs},-label=>'numSegments',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>0,-column=>0,-sticky=>'e');
    $int_fr->LabEntry(-textvariable=>\$rps->{integration}{segExponent},-label=>'segExponent',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>1,-column=>0,-sticky=>'e');
    $int_fr->LabEntry(-textvariable=>\$rps->{integration}{t0},-label=>'t0',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>2,-column=>0,-sticky=>'e');
    $int_fr->LabEntry(-textvariable=>\$rps->{integration}{t1},-label=>'t1',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>3,-column=>0,-sticky=>'e');
    $int_fr->LabEntry(-textvariable=>\$rps->{integration}{dt0},-label=>'dt0',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>4,-column=>0,-sticky=>'e');
    $int_fr->LabEntry(-textvariable=>\$rps->{integration}{minDt},-label=>'minDt',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>5,-column=>0,-sticky=>'e');
    $int_fr->LabEntry(-textvariable=>\$rps->{integration}{plotDt},-label=>'plotDt',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>6,-column=>0,-sticky=>'e');
    $int_fr->LabEntry(-textvariable=>\$rps->{integration}{plotZScale},-label=>'plotZMagnification',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>7,-column=>0,-sticky=>'e');

    my $debugVerboseField;
    if (DEBUG){
        $debugVerboseField = $int_fr->LabEntry(-textvariable=>\$rps->{integration}{debugVerbose},-label=>'debugVerbose',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>8,-column=>0,-sticky=>'e');
    } else {
        $debugVerbose = 3;  # The only thing that makes sense in this situation.
    }

    my @aStepperItems = ("msbdf_j","rk4imp_j","rk2imp_j","rk1imp_j","bsimp_j","rkf45","rk4","rk2","rkck","rk8pd","msadams");
    $int_fr->Optionmenu(-options=>\@aStepperItems,-variable=>\$rps->{integration}{stepperItem},-textvariable=>\$rps->{integration}{stepperName},-relief=>'sunken')->grid(-row=>9,-column=>0,-sticky=>'e');

    my $saveOptionsMB = $int_fr->Menubutton(-state=>'normal',-text=>'saveOptions',-relief=>'sunken',-direction=>'below',-width=>12)->grid(-row=>10,-column=>0,-sticky=>'e');
        my $saveOptionsMenu = $saveOptionsMB->Menu();
            $saveOptionsMenu->add('checkbutton',-label=>'plot',-variable=>\$rps->{integration}{savePlot});        
            $saveOptionsMenu->add('checkbutton',-label=>'data',-variable=>\$rps->{integration}{saveData});    
        $saveOptionsMB->configure(-menu=>$saveOptionsMenu);   # Attach menu to button.

    my $verboseField = $int_fr->LabEntry(-textvariable=>\$rps->{integration}{verbose},-label=>'verbose',-validate=>'key',-validatecommand=>\&OnVerbose,-invalidcommand=>undef,-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>11,-column=>0,-sticky=>'e');



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


# RUN ==================================

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
OnVerbose($rps->{integration}{verbose});
$debugVerbose = $rps->{integration}{debugVerbose};
#print "debugVerbose=$debugVerbose\n";

# Start the main event loop
MainLoop;

exit 0;

# Utility Functions ==============

# My redefinition of the Tk error handler.  See https://metacpan.org/pod/distribution/Tk/pod/Error.pod  Tk captures die and croak, sends the data here, and terminates the subroutine call appropriately.  Note that it is documented if the error message ends with "\n", die suppresses the "at ...." data string.  I'm encouraging the use of "...\nStopped" form error messages, since the code below will filter out all that follows in $verbose<=2.  Use confess to see the whole calling sequence if $verbose>=3.
sub Tk::Error {
    my ($widget,$error,@locations) = @_;

    if ($verbose<=2){
        my $index = CORE::rindex($error,"\nStopped at",length($error)-1);
        if ($index != -1){
            $error = substr($error,0,$index+1);
        }
    }
    print $error;
    if ($verbose>=3){print "\n@locations\n"}
    # For clarity for the user, suppress location (Tk calling sequence) pq(\@locations) unless we are looking at detailed printouts.
    
    OnStop();
}


sub HashCopy {      # Require identical structure.  No checking.
    my ($r_src,$r_target) = @_;
    
    foreach my $l0 (keys %$r_target) {
        foreach my $l1 (keys %{$r_target->{$l0}}) {
            $r_target->{$l0}{$l1} = $r_src->{$l0}{$l1};
        }
    }
}


sub StrictRel2Abs {
	my ($relFilePath,$baseDirPath) = @_;

	# Start navigating where the last save was located:
	my ($volume,$dirs,$filename);
	if ($relFilePath){
		($volume,$dirs,$filename) = splitpath($relFilePath);
		$dirs = rel2abs($dirs,$baseDirPath);
	} else {
		$filename = '';
		$dirs = $baseDirPath;
	}
	
	#pq($dirs,$filename);
	
	return ($dirs,$filename);
}



# Action Functions ==============

sub OnVerbose {
    my ($propVal,$newChars,$currVal,$index,$type) = @_;
    
    ## There is difficulty which I don't see through when I try to use validatecommand and invalidcommand to change the textvariable.  For my purposes, I can use the verbose entry as in effect read only, just changing the field value from empty to 0 on saving prefs.  I got the code below online.  The elegant thing in making 'key' validation work is to allow empty as zero.
 
    #print "Entering OnVerbose: ($propVal,$newChars,$currVal,$index,$type)\n";
    #print "Before: verbose=$verbose\n";
    
    my $val = shift;
    $val ||= 0;   # Make empty numerical.
    # Get alphas and punctuation out
    if( $val !~ /^\d+$/ ){ return 0 }
    if (($val >= 0) and ($val <= 10)) {
        $verbose = $propVal;
        if ($verbose eq ''){$verbose = 0}
        $vs = ($verbose<=1 and $verbose>$tieMax)?"                                   \r":"\n";
            # Kluge city! to move any junk far to the right.  However, I also can't get \r to work correctly in TK RO, so when writing to status rather than terminal, I just newline.
        SetTie($verbose);
#print "thisLine0 $vs nextLine0\n";     # see if \r works
        #print "After: verbose=$verbose\n";
        
        return 1;
    }
    else{ return 0 }
}

=begin comment

sub VerboseInvalid {
    my ($propVal,$newChars,$currVal,$index,$type) = @_;
    
    ## I leave this here as an example, but do without it.
    
print "In INVALID: ($propVal,$newChars,$currVal,$index,$type)\n";
#        if( $currVal !~ /^\d+$/ ){ $currVal = 0}
    if (defined($currVal)){
        if( $currVal eq "" ){
#            $verbose = 0;
        }else{
            $verbose = $currVal;
        }
    }

# Make sure we haven't turned validate off:
#    $int_fr->LabEntry->configure(-validate => 'key');

    return 1; # ??
}

=end comment

=cut

sub ChangeVerbose {
    my ($newVerbose) = @_;
    #print "Entering ChangeVerbose: verbose=$verbose,newVerbose=$newVerbose\n";
    $rps->{integration}{verbose} = $newVerbose;
    #pq($newVerbose);die;
    OnVerbose($rps->{integration}{verbose});    # Simply setting does not validate.
    #print "Exiting ChangeVerbose:  verbose=$verbose\n";
}


sub SetTie {
    my ($verbose) = @_;
    
    ## This is a bit subtle since to make 'key' work, I need to allow $verbose==''.  That will momentarily switch to status here, but nothing should be written.

    if ($verbose eq ''){die "\nASTONISHED THAT I AM CALLED.\n\nStopped"}   # Noop.
    
    elsif ($verbose<=$tieMax){
        tie *STDOUT, ref $status_rot, $status_rot;
        tie *STDERR, ref $status_rot, $status_rot;
    }else{
no warnings;
        untie *STDOUT;
        untie *STDERR;
use warnings;
    }
}


sub LoadSettings {
    my ($filename) = @_;
    my $ok = 0;
    if ($filename) {
        if (-e $filename) {
            my $conf = Config::General->new($filename);
            my %src = $conf->getall();
            if (%src){
                if (exists($src{file}{rSwing})) {           
                    HashCopy(\%src,$rps);
                        # Need to copy so we don't break entry textvariable references.
                    $verbose = $rps->{integration}{verbose};
                    $ok = 1;
                } else {
                    print "\n File $filename is corrupted or is not an RSwing settings file.\n";
                }
            }
        }
    }
    return $ok;
}



my @types = (["Config Files", '.prefs', 'TEXT'],
       ["All Files", "*"] );


sub OnSettingsSelect {

	my ($dirs,$filename) = StrictRel2Abs($rps->{file}{settings},$exeDir);

    my $FSref = $mw->FileSelect(-directory=>$dirs,-defaultextension=>'.prefs');
    $FSref->geometry('700x500');
    $filename = $FSref->Show;
	
    if ($filename){
        if (LoadSettings($filename)){
            $rps->{file}{settings} = abs2rel($filename,$exeDir);
            LoadLine($rps->{file}{line});
            LoadLeader($rps->{file}{leader});
            LoadDriver($rps->{file}{driver});
            UpdateFieldStates();
            
        }else{
            $rps->{file}{settings} = '';
            warn "Error:  Could not load settings from $filename.  Retaining previous settings file\n";
        }
    }
}

sub OnSettingsNone {
    $rps->{file}{settings} = '';
}



sub OnLineSelect {

	my ($dirs,$filename) = StrictRel2Abs($rps->{file}{line},$exeDir);

    my $FSref = $mw->FileSelect(-directory=>$dirs,-defaultextension=>'.txt');
    $FSref->geometry('700x500');
    $filename = $FSref->Show;
    if ($filename){
		$rps->{file}{line} = abs2rel($filename,$exeDir);
        SetFields(\@lineFields,"-state","disabled");
    }
}

sub OnLineNone {
    $rps->{file}{line} = '';
    SetFields(\@lineFields,"-state","normal");
}

sub OnLeaderSelect {

	my ($dirs,$filename) = StrictRel2Abs($rps->{file}{leader},$exeDir);

    my $FSref = $mw->FileSelect(-directory=>$dirs,-defaultextension=>'.txt');
    $FSref->geometry('700x500');
    $filename = $FSref->Show;
    if ($filename){
		$rps->{file}{leader} = abs2rel($filename,$exeDir);
        SetFields(\@leaderFields,"-state","disabled");
    }
}

sub OnLeaderNone {
    $rps->{file}{leader} = '';
    SetFields(\@leaderFields,"-state","normal");
}

sub OnDriverSelect {

	my ($dirs,$filename) = StrictRel2Abs($rps->{file}{driver},$exeDir);

    my $FSref = $mw->FileSelect(-directory=>$dirs,-filter=>'(*.txt)|(*.svg)');
    $FSref->geometry('700x500');
    $filename = $FSref->Show;
    if ($filename){
		$rps->{file}{driver} = abs2rel($filename,$exeDir);
        SetFields(\@driverFields,"-state","disabled");
    }
}

sub OnDriverNone {
    $rps->{file}{driver} = '';
    SetFields(\@driverFields,"-state","normal");
}


sub OnSaveSettings{

	my ($dirs,$filename) = StrictRel2Abs($rps->{file}{settings},$exeDir);

    $filename = $mw->getSaveFile(   -defaultextension=>'',
                                    -initialfile=>"$filename",
                                    -initialdir=>"$dirs");

    if ($filename){

        # Tk prevents empty or "." as filename, but let's make sure we have an actual basename, then put our own suffix on it:
        my ($basename,$dirs,$suffix) = fileparse($filename,'.prefs');
        if (!$basename){$basename = 'untitled'}
        $filename = $dirs.$basename.'.prefs';

        # Insert the selected file as the settings file:
		$rps->{file}{settings} = abs2rel($filename,$exeDir);
		
        my $conf = Config::General->new($rps);
        $conf->save_file($filename);
    }
}


sub OnRunPauseCont{
    
    my $label = $runPauseCont_btn ->cget(-text);
    
    switch ($label)  {
        case "RUN"          {
            print "RUNNING$vs";
            if (!RSwingSetup()){print "RUN ABORTED$vs"; return}
            next;
        }
        case "CONTINUE" {
            print "CONTINUING$vs";
            next;
        }
        case ["CONTINUE","RUN"]     {
            #print "CR$vs";
            $runPauseCont_btn ->configure(-text=>"PAUSE");
            
            SetDescendants($files_fr,"-state","disabled");
            SetDescendants($params_fr,"-state","disabled");
            SetOneField($verboseField,"-state","normal");
            if ($debugVerboseField){
                SetOneField($debugVerboseField,"-state","normal");
                # Keep verbose user settable.
            }
            
            $rSwingRunControl{callerRunState} = 1;
            RSwingRun();
            
        }
        case "PAUSE"        {
            print "PAUSED$vs";
            $rSwingRunControl{callerRunState} = -1;
            $runPauseCont_btn ->configure(-text=>"CONTINUE");
        }
    }
}


sub OnStop{

    $rSwingRunControl{callerRunState} = 0;
    $runPauseCont_btn ->configure(-text=>"RUN");
    print "STOPPED$vs";

    SetDescendants($files_fr,"-state","normal");
    SetDescendants($params_fr,"-state","normal");
    
    UpdateFieldStates();
}



sub OnSaveOut{

	# Start navigating where the last save was located:
	my ($dirs,$filename) = StrictRel2Abs($rps->{file}{save},$exeDir);

    $filename = $mw->getSaveFile(   -defaultextension=>'',
                                    -initialfile=>"$filename",
                                    -initialdir=>"$dirs");

    if ($filename){

        # Tk prevents empty or "." as filename, but let's make sure we have an actual basename.  The saving functions will put on their own extensions:
		my $basename;
        ($basename,$dirs) = fileparse($filename,'');
        if (!$basename){$basename = 'untitled'}
        $filename = $dirs.$basename;

        # Insert the selected file as the save file:
		$rps->{file}{save} = abs2rel($filename,$exeDir);
		
        RSwingSave($filename);
        #RSwingPlotExtras($filename);  Not yet entirely implemented.
    }
}


sub SetOneField {
    my ($field,$option,$state) = @_;
    
    my $as = $field->cget(-state);
    if ($as) {$field->configure("$option"=>"$state")}
}


sub SetFields {
    my ($fields,$option,$state) = @_;
    
    foreach $a (@$fields){
        my $as = $a->cget(-state);
        if ($as) {$a->configure("$option"=>"$state")}
    }
}


sub UpdateFieldStates {
    
    if ($rps->{file}{line}){SetFields(\@lineFields,"-state","disabled")}
    else {SetFields(\@lineFields,"-state","normal")}
    
    if ($rps->{file}{leader}){SetFields(\@leaderFields,"-state","disabled")}
    else {SetFields(\@leaderFields,"-state","normal")}
    
    if ($rps->{file}{driver}){SetFields(\@driverFields,"-state","disabled")}
    else {SetFields(\@driverFields,"-state","normal")}
    
}


sub SetDescendants {
    my ($self,$option,$state) = @_;
    my @children = $self->children;

    foreach $a (@children){
        my $as = $a->cget(-state);
        if ($as) {$a->configure("$option"=>"$state")}
        SetDescendants($a,$option,$state);
    }
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
	 ['command', 'About', -command=>[\&OnAbout]],
	 ['command', 'Params-Line,Etc', -command=>[\&OnLineEtc]],
	 ['command', 'Params-Stream,Etc', -command=>[\&OnStreamEtc]],
	 ['command', 'Params-Config,Etc', -command=>[\&OnConfigEtc]],
	 ['command', 'Params-Integ,Etc', -command=>[\&OnIntegEtc]],
	 ['command', 'Params-Verbose', -command=>[\&OnVerboseParam]],
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
		   -title=>"About RHexSwing3D",
		   -buttons=>["OK"]
		   );

    # Now we need to add a Label widget so we can show some text.  The
    # DialogBox is essentially an empty frame with no widgets in it.
    # You can images, buttons, text widgets, listboxes, etc.
    $about->add('Label',
		-anchor=>'w',
		-justify=>'left',
		-text=>qq(
RHexSwing3D 1.1, by Rich Miller, 2019

This is a program that simulates the motion of a multi-component fly line (line proper, leader,
tippet and fly) in a flowing stream under the influence of gravity, buoyancy, fluid friction,
internal stresses, and a user defined initial configuration, rod tip motion, and line stripping.
    
The results of the calculation are displayed as constant-time-interval colored traces on a 3D plot
that can be rotated at will by the motion of the cursor.  The earliest traces are shown in green and
the latest in red, with the intermediate traces shown as brownish shades that are the combination of
green and red in appropriate proportion.  Open circles, solid circles, diamonds and squares mark the
locations of the rod tip, line-leader and leader-tippet junctions, and the fly.
    
The interactive control panel allows the setting of parameters that control the details of the line
make-up, the water flow, the initial line location, the rod tip movement, the stripping starting
time and velocity, and details of the integration and plotting.  In addition, the panel allows for
the selection of a parameter preference file, which presets all the parameters to a
previously saved condition, as well as the selection of a file that defines a specific fly-line,
and of another that loads a textual description of a rod-tip motion.  Use of the line and motion
files allows the simulation of any fly line with any motion, not just those constructable using the
parameters.
    
Once you have set the parameters to your liking, press the run button to begin the computation at
the nominal start time (t0).  The report interval (plotDt) sets the times at which traces are drawn.
When the run starts, the parameters are range-checked for validity.  Range violations that preclude
program execution generate error messages.  You must correct these errors and try again.  Other
settings, that merely are outside the usual expected range, generate warnings that tell you what
the expected range is, but do no stop the run.  You can stop it yourself and make changes if you
want.
    
Depending on the value of the parameter verbose, more or less runtime output will be shown.
Verbose = 0 shows only the run identifier and any errors which stop the run.  Verbose = 1 shows
warnings as well as errors, and also a few of the major mileposts of the computation.  Verbose = 2
shows all these things as well as showing the progress in nominal time and giving an indication of
how much work the integrator needs to do to get from one reported time step to the next.  This is
probably the best general setting.  You get a good feel for how the computation is going, without
causing it to slow down very much.  At any time, you can press the pause button to get the output
plot as of that time.  If you subsequently hit the continue button, the calculation will resume at
the last reliable plotted time, which is the last one at one of the uniform steps.
    
If you hit the stop button, the execution stops and cannot be resumed.  You will, however, be shown
the data plot up to that time.  The program will also stop and show you the results plot when the
nominal time reaches the selected end time (t1).  In order to change parameters the program must be
stopped, not merely paused.  At any time when the program is not running, you can press the save out
button to save the current plot to a file for future viewing or other use.  Depending on the setting
of the save options, other data may also be saved to a file.
    
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


# Show the Help->About Dialog Box
sub OnLineEtc {
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
FLY LINE:

totalLength - The combined length in feet of the part of the fly line outside the tip guide, the
	leader, and the tippet.  It must be positive. Typical range is [10,50].

nominalWeight - Fly line nominal weight in grains per foot. For tapered lines, this is supposed to
	be the average grains per foot of the first 30 feet of line.  Must be non-negative. The typical
	range [1,15].  About 15 grains make one gram, and 437.5 grains make one ounce.
    
estimatedDensity - Fly line density. Non-dimensional.  Used for computing diameters when only
	weights per foot are known.  Must be positive.  Typical range is [0.5,1.5].  Densities less
	than 1 float in fresh water, greater than 1 sink.

nominalDiameter - In inches.  Used only for level lines.  Must be non-negative. Typical range is
	[0.030,0.090].

coreDiameter - The braided or twisted core of a coated fly line provides most of the tensile
	strength and elastic modulus.  The diameter in inches.  Must be non-negative.  Typical range
	is [0.010,0.050].
    
coreElasticModulus - Also known as Young\'s Modulus, in pounds per square inch.  Dependent on the
	type of material that makes up the core.  Must be non-negative.  Typical range is [1e5,4e5],
	that is, [100,000 - 400,000].
    
dampingModulus - In pounds per square inch.  Dependent on the material type.  Must be non-negative.
	A hard number to come by in the literature.  However, it is very important for the stability of
	the numerical calculation.  Values much different from 1 slow the solver down a great deal,
	while those much above 10 lead to anomalies during stripping.


LEADER:
    
length - In feet. Must be non-negative.  Typical range is [5,15].

weight - In grains per foot.  Used only for level leaders.  Weight must be non-negative. Typical
	range for sink tips is [7,18].

diameter - In inches.  Used only for level leaders.  Must be positive. Typical range is
	[0.004,0.050], with sink tips in the range [0.020,0.050].


TIPPET (always level):

length - In feet. Must be non-negative. Typical range is [2,12].

diameter - In inches.  Must be non-negative. Typical range is [0.004,0.012]. Subtract a tippet
	X value from 0.011 inches to convert X\'s to inches.


FLY:

weight - In grains. Must be non-negative.  Typical range is [0,15], but a very heavy intruder
	might be as much as 70.

nominalDiameter - In inches.  To account for the drag on a fly, we estimate an effective
	drag diameter and effective drag length.  Nominal diameter must be non-negative. Typical range
	is [0.1,0.25].

nominalLength - In inches.  Must be non-negative. Typical range is [0.25,1].

estimatedDisplacement - In cubic inches.  To account for buoyancy, we need to estimate the actual
	volume displaced by the fly materials.  This is typically very much less than the drag volume
	computed from the drag diameter and length described above.  Fly nom volume must be non-
	negative. On small flies this may be just a little more than the volume of the hook metal.
	Typical range is [0,0.005].
}
		)->pack;

    $params->Show();
}


sub OnStreamEtc {
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


STREAM

surfaceVelocity - Water surface velocity in feet per second at the center of the stream.  Must be
	non-negative. Typical range is [1,7], a slow amble to a very fast walk.

surfaceLayerThickness - Water surface layer thickness in inches.  Mostly helpful to the integrator
	because it smooths out the otherwise sharp velocity break between the (assumed) still air and
	the flowing water.  Must be must be non-negative. Typical range is [0.1,2].

bottomDepth - Bottom depth in feet.  In our model, the entire stream is uniformly deep, and the flow
	is always parallel to the X-axis, which points downstream along the stream centerline.  Must be
	must be non-negative.  Frictional effects of the bottom on the water are important, especially
	under the good assumption of an exponential profile of velocity with depth.  See below. Typical
	range is [3,15].

halfVelocityThickness - In feet.  Only applicable to the case of exponetial velocity variation with
	depth.  Half thickness must be positive, and no greater than half the water depth. Typical range
	is [0.2,3].  A small half-thickness means a thinner boundary layer at the stream bottom.

horizontalHalfWidth - The cross-stream distance in feet from the stream centerline to the point
	where, at any fixed depth, the downstream velocity is half of its value at that depth at the
	stream centerline.  Must be positive. Typical range is [3,20].

horizontalExponent - Sets the relative square-ness of the cross-stream velocity profile.  Must be
	either 0 or greater than or equal to 2.  Zero means no cross-stream variation in velocity.
	Larger values give less rounded, more square cross-stream profiles. Typical range is 0 or [2,10].

showVelocityProfile - If non-zero (say, 1), a graph of the vertical velocity profile is drawn before
	the calculation begins.  If 0, this plot is not drawn.  Draw the profile to get a feeling for the
	effect of varying half-velocity thicknesses.  If the cross-stream profile is not constant, and
	this parameter is not 0, a second plot showing the cross-stream drop-off will also be drawn.
}
		)->pack;

    $params->Show();
}


sub OnConfigEtc {
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
INITIAL LINE CONFIGURATION

rodTipToFlyAngle - Sets the cross-stream angle in degrees at the start of the integration.  Must be in the
	range (-180,180).  Zero is straight downstream, 90 is straight across toward river left, -90 is straight
	across toward river right, and 180 is straight upstream.

lineCurvature - In units of 1\/feet. Equals 1 divided by the radius of curvature.  With the direction from
	the rod tip to the fly set as above, non-zero line curvature sets the line to bow along a horizontal
	 circular arc, either convex downstream (positive curvature) or convex upstream (negative curvature).
	 The absolute value of the curvature must be no greater than 2\/totalLength.  Initial curvature corresponds
	 to the situation where a mend was thrown into the line before any significant drift has occurred.

preStretchMultiplier - Values greater than 1 cause the integration to start with some amount of stretch in the
	line.  Values less than 1 start with some slack.  This parameter was originally	inserted to help the
	integrator get started, but doesn\'t seem to have an important effect.	Must be no less than 0.9. Typical
	range is [1,1.1].

tuckHeight - Height in feet above the water surface of the fly during a simulated tuck cast.  Must be non-
	negative. Typical range is [0,10].

tuckVelocity - Initial downward velocity of the fly in feet per second at the start of a simulated tuck cast.
	Must be non-negative. Typical range is [0,10].


LINE MANIPULATION AND ROD TIP MOTION

laydownInterval - In seconds.  Currently unimplemented.  The time interval during which the rod tip is moved
	down from its initial height to the water surface.  Must be non-negative. Typical range is [0,1].

sinkInterval - In seconds.  Only applicable when stripping is turned on.  This is the interval after the start
	of integration during which the fly is allowed to sink before stripping starts. Must be must be non-
	negative. Typical range is [0,35], with the longer intervals allowing a full swing before stripping in the
	near-side soft water.

stripRate - In feet per second.  Once stripping starts, only constant strip speed is implemented. Strip rate
	must be must be non-negative. Typical range is [0,5].  Zero means no stripping.

rodTipStartCoords - In feet.  Sets the initial position of the rod tip.  Must be of the form of	three comma
	separated numbers, X,Y,Z. Typical horizontal values are less than an arm plus rod length plus active line
	length, while typical vertical values are less than an arm plus rod length.

rodTipEndCoords - Same form and restrictions as for the start coordinates.

If the start and end coordinates are the same, there is no motion.  This is one way to turn off motion.  The
	other way is to make the motion start and end times equal (see below).

rodPivotCoords - Same form as the start coordinates.  These coordinates are irrelevant if the rod tip track is
	set as a straight line between its start and end.  However if the tip track is curved (see below), the
	pivot, which you may envision as your shoulder joint, together with the track starting and ending points
	defines a plane.  In the current implementation, the curved	track is constrained to lie in that plane.
	Typically the distance between the pivot and the start and between the pivot and the end of the rod tip
	track is less than the rod plus arm length.  The typical pivot Z is about 5 feet.

trackCurvature - In units of 1\/feet. Equals 1 divided by track the radius of curvature. Sets the amount of bow
	in the rod tip track.  Must have absolute value less than 2 divided by the distance between the track start
	and the track end.  Positive curvature is away from the pivot, negative curvature, toward it.

trackSkewness - Non-zero values skew the curve of the track toward or away from the starting location, allowing
	tracks that are not segments of a circle.  Positive values have peak curvature later in the motion.
	Typical range is [-0.25,0.25].

motionStart and End times - In seconds.  If the end time is earlier or the same as the start time, there is no
	motion.

motionVelocitySkewness - Non-zero causes the velocity of the rod tip motion to vary in time. Positive causes
	velocity to peak later.  Typical range is [-0.25,0.25].

showTrackPlot - Non-zero causes the drawing, before the integration starts, of a rotatable 3D plot showing the
	rod tip track.  You can see the same information at the end of the integration by looking at the rod tip
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

numberOfSegments - The number of straight segments into which the line is divided for the purpose of calculation.
	The integrator follows the time evolution of the junctions of these segments.  Must be an integer >= 1.
	Larger numbers of segments mean a smoother depiction of the line motion, but come at the cost of longer
	calculation times.  These times vary with the 3rd power of the number of segments, so, for example, 20
	segments will take roughly 64 times as long to compute as 5 segments. Typical range is [5,20].  It is often a
	good strategy to test various parameter setups with 5 segments, and when you have approximately what you want,
	go to 15 or even 20 for the final picture.

segmentsExponent - Values different from 1 cause the lengths of the segments to vary as you go from the rod tip
	toward the fly.  The exponent must be positive.  Values less than 1 make the segments near the rod tip longer
	than those near the fly.  This is usually what you want, since varying the lengths but not the number does not
	change computational cost (that is, time), and it is generally desirable to have more detail in the leader and
	tippet than in the fly line proper.  Typical range is [0.5,2].

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

plotZScale - Allows for changing the magnification of the plotted Z-axis relative to the plotted X- and Y-axes.
	Magnification must be no less than 1. Typical range is [1,5].  This magnification only affects display, not the
	underlying computed data.  The replot program allows redisplay at a different vertical magnification.

integrationStepperChoice - This menu allows you to choose from among 11 different stepper algorithms.  Some work
	better (are faster and more reliable) in some situations, and others work better in other situations.  However,
	for our purposes, the first choice, msbdf_j, seems to give the best results.

saveOptions - When you hit the Save Out button if the \"plot\" box is checked (colored red), an .eps picture file
	of the results will be created and saved.  This picture can be attached to an email or viewed in any of a
	number of programs.  In particular, on the mac, it can be opened in Preview.  However, this picture is
	\"static\".  What you see is what you get.  You can only resize it.  This is unlike the \"live\" plot that is
	shown when a RHexSwing3D run is paused or completes, which can be rotated any which way using the mouse.  On
	the other hand, if you check the \"data\" box, a text file is created.  That file can be opened in any text
	editor, and you can read the actual coordinate numbers that define the traces, as well as the parameter
	settings that gave rise to those traces.  In addition, that file can be opened in RHexReplot3D, and from there
	replotted in live, rotatable form.
}
		)->pack;

    $params->Show();
}


sub OnVerboseParam {
    # Construct the DialogBox
    my $params = $mw->DialogBox(
		   -title=>"Verbose Param",
		   -buttons=>["OK"]
		   );

    # Now we need to add a Label widget so we can show some text.  The
    # DialogBox is essentially an empty frame with no widgets in it.
    # You can images, buttons, text widgets, listboxes, etc.
    $params->add('Label',
		-anchor=>'w',
		-justify=>'left',
		-text=>qq{
VERBOSE:

verbose - Allows you to specify the amount of textual information that is displayed during an integrator run.  You
	can set the value to any of the integers in the range 0 to 3 inclusive.  The higher the number, the more
	information displayed.  Numbers less than or equal to 2 are essentially cost free, and setting verbose to 2 is
	generally the best choice, since it gives you a satisfying graphic depiction of the progress of the
	calculation.  This, among other things, lets you chose opportune moments to pause the run and view a plot of
	the swing up to that time.  Verbose set to 0 prints only the most general indication that the program is
	running or stopped, as well as actual error messages that mean that the calculation cannot start or proceed for
	some reason, typically because you have used unallowed parameter values, but also sometime because there is a
	programming bug that needs to be corrected.  Verbose set to 1 additionally prints warnings about typical ranges
	of parameters.  Verbose set to 2 prints all these things, plus indicating progress through the run setup
	procedure, plus the progress graphic and a few more details about computation times and the like.  One
	interesting special feature, is that if you have a level leader, its still water sink rate is computed.  It is
	often of interest to compare this number to the manufacturer\'s advertised value.  For verbose less than or
	equal to 2, all the output appears in the status pane on the control panel.  There is a scroll bar on the right
	hand edge of the pane that lets you look back at text that passed by earlier.

Verbose equal to 3 is an entirely different animal.  It generates a lot more output, which includes, at each
	integrator test step, a listing of all the forces exerted on the segment centers of gravity, including
	gravitation, buoyancy, and fluid drag, as well as the tension and dissipative forces acting along the segments.
	All these forces balance against inertial forces due to the segment masses to determine the dynamics of the
	swing.  Printing all this slows down the calculation quite a bit, but can be fascinating to look at, especially
	if something counter intuitive is happening.  To accomodate all this output, the program is set up print it in
	the much larger Terminal application window that is automatically created when RHexSwing3D is launched.  In
	addition to capacity, the terminal window has two very important other advantages:  it is searchable with the
	standard mac mechanisms, and is savable to a file, so you can keep the run details for as long as you want.
}
		)->pack;

    $params->Show();
}


#evaluates code in the entry text pane
sub OnEval{
}

__END__


=head1 NAME

RHexSwing3D - A PERL program that simulates the motion of a multi-component fly line (line proper,
leader, tippet and fly) in a flowing stream under the influence of gravity, buoyancy, fluid friction,
internal stresses, and a user defined initial configuration, rod tip motion, and line stripping.
RHexSwing3D is one of the two main programs of the RHex Project.


=head1 SYNOPSIS

Enter perl RHexSwing3D.pl in a terminal window, or double-click on the shell script RHexSwing3D.sh
in the finder window, or run the stand-alone executable RHexSwing3D if it is available.
  
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

The code in this file builds and deploys the control panel, whose buttons invoke functions in RSwing3D.pm
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

Copyright (C) 2019 by Rich Miller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.28.1 or,
at your option, any later version of Perl 5 you may have available.

=cut


