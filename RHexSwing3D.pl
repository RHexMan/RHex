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

# Compile directives ==================================
#package RHexSwing3D;
use lib (".");  # See https://perldoc.perl.org/lib.html. Avoids having to put . in the path.

use RSwing3D;    # For verbose, right away.
use RPrint;

chomp(my $exeName = `echo $0`); 
    # Gets rid of the trailing newline with which shell commands finish.
chomp(my $exeDir  = `dirname $0`);
#print "exeDir = $exeDir\n";
chdir "$exeDir";  # See perldoc -f chdir
#`cd $exeDir`;   # This doesn't work, but the perl function chdir does!
chomp($exeDir = `pwd`);  # Force full pathname.
if ($verbose){print "Running $exeName @ARGV, working in $exeDir.\n"}

my $nargs = @ARGV;
if ($nargs>1){die "\n$0: Usage:RSwing.pl [settingsFile]\n"} 

# --------------------------------

use warnings;
use strict;

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
my $stream_fr   = $params_fr->Labelframe(-text=>"Stream\n & Starting Line Configuration")->pack(qw/-side left -fill both -expand 1/);
my $driver_fr   = $params_fr->Labelframe(-text=>"Rod Tip Track")->pack(qw/-side left -fill both -expand 1/);
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
    $stream_fr->LabEntry(-textvariable=>\$rps->{configuration}{crossStreamAngleDeg},-label=>'flyToRodTipAngle(deg)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>8,-column=>0,-sticky=>'e');
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
    my $FSref = $mw->FileSelect(    -defaultextension=>'.prefs');
    $FSref->geometry('700x500');
    my $filename = $FSref->Show;
    if ($filename){
        if (LoadSettings($filename)){
            $rps->{file}{settings} = $filename;
            LoadLine($rps->{file}{line});
            LoadLeader($rps->{file}{leader});
            LoadDriver($rps->{file}{driver});
            UpdateFieldStates();
            
        }else{
            $rps->{file}{settings} = '';
            warn "Error:  Could not load settings from $filename.\n";
        }
    }
}

sub OnSettingsNone {
    $rps->{file}{settings} = '';
}



sub OnLineSelect {
    my $FSref = $mw->FileSelect(-defaultextension=>'.txt');
    $FSref->geometry('700x500');
    my $filename = $FSref->Show;
    if ($filename){
        $rps->{file}{line} = $filename;
        SetFields(\@lineFields,"-state","disabled");
    }
}

sub OnLineNone {
    $rps->{file}{line} = '';
    SetFields(\@lineFields,"-state","normal");
}

sub OnLeaderSelect {
    my $FSref = $mw->FileSelect(-defaultextension=>'.txt');
    $FSref->geometry('700x500');
    my $filename = $FSref->Show;
    if ($filename){
        $rps->{file}{leader} = $filename;
        SetFields(\@leaderFields,"-state","disabled");
    }
}

sub OnLeaderNone {
    $rps->{file}{leader} = '';
    SetFields(\@leaderFields,"-state","normal");
}

sub OnDriverSelect {
    my $FSref = $mw->FileSelect(    -filter=>'(*.txt)|(*.svg)');
    $FSref->geometry('700x500');
    my $filename = $FSref->Show;
    if ($filename){
        $rps->{file}{driver} = $filename;
        SetFields(\@driverFields,"-state","disabled");
    }
}

sub OnDriverNone {
    $rps->{file}{driver} = '';
    SetFields(\@driverFields,"-state","normal");
}


sub OnSaveSettings{
    my $filename = $rps->{file}{settings};
    my($basename,$dirs,$suffix) = fileparse($filename,'.prefs');
    $filename = $mw->getSaveFile(   -defaultextension=>'',
                                    -initialfile=>$basename,
                                    -initialdir=>"$dirs");

    if ($filename){

        # Tk prevents empty or "." as filename, but let's make sure we have an actual basename, then put our own suffix on it:
        ($basename,$dirs,$suffix) = fileparse($filename,'.prefs');
        if (!$basename){$basename = 'untitled'}
        $filename = $dirs.$basename.'.prefs';

        # Insert the selected file as the settings file:
        $rps->{file}{settings} = $filename;
        
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

    my $filename = $rps->{file}{save};
    my($basename,$dirs,$suffix) = fileparse($filename,'');
    my $settingsDir = dirname($rps->{file}{settings});
    $filename = $mw->getSaveFile(   -defaultextension=>'',
                                    -initialfile=>$basename,
                                    -initialdir=>"$settingsDir");

    if ($filename){

        # Tk prevents empty or "." as filename, but let's make sure we have an actual basename.  The saving functions will put on their own extensions:
        ($basename,$dirs,$suffix) = fileparse($filename,'');
        if (!$basename){$basename = 'untitled'}
        $filename = $dirs.$basename;

        pq($dirs,$basename,$suffix,$filename);
        # Insert the selected file as the save file:
        $rps->{file}{save} = $filename;
        
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
		   -title=>"About RSwing3D",
		   -buttons=>["OK"]
		   );

    # Now we need to add a Label widget so we can show some text.  The
    # DialogBox is essentially an empty frame with no widgets in it.
    # You can images, buttons, text widgets, listboxes, etc.
    $about->add('Label',
		-anchor=>'w',
		-justify=>'left',
		-text=>qq(
RSwing3D 1.1, by Rich Miller, 2019

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


#evaluates code in the entry text pane
sub OnEval{
}
