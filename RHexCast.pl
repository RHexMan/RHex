#!/usr/bin/perl -w

## If run with one arg, it is taken to be the .prefs file.  Generally, when loading, file navigation will start with the exe dir, and when saving, with the directory that holds the current settings file if there is one, otherwise with the exe dir.  That will encourage outputs associated with "related" settings to settle naturally in one folder.

# ------- Startup -------------------------
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

use RCast3D;    # For verbose, right away.

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

use Config::General;
use Switch;     # WARNING: switch fails following an unrelated double-quoted string literal containing a non-backslashed forward slash.  This despite documentation to the contrary.
use File::Basename;

#use Tie::Watch;
    # Keep this in mind for general use.  However, for widgets, one can usually use the -validate and -validatecommand options to do what we want.
    # For redirecting STOUT when $verbose changes.  Maybe we can do this directly in TK.
#use Try::Tiny;  # Try to keep our validation from going away. DOESN'T WORK.


my $rps = \%rHexCastRunParams;

my $defaultSettingsFile = $rps->{file}{settings};
# Save a copy from startup values in RHexCastPkg.  During running of this program the value may be overwritten.


# Main Window
my $mw = new MainWindow;
$mw->geometry('1150x650+50+0');
$mw->resizable(0,0);

$RHexCastRunControl{callerUpdate}   = sub {$mw->update};
$RHexCastRunControl{callerStop}     = sub {OnStop()};
$RHexCastRunControl{callerRunState} = 0;   # 1 keep running, -1 pause, 0 stop.

#$rSinkTipRunControl{callerUpdate}   = sub {$mw->update};
#$rSinkTipRunControl{callerStop}     = sub {OnStop()};
#$rSinkTipRunControl{callerRunState} = 0;   # 1 keep running, -1 pause, 0 stop.

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
my $line_fr         = $params_fr->Labelframe(-text=>"Line")->pack(qw/-side left -fill both -expand 1/);
my $tip_fr          = $params_fr->Labelframe(-text=>"Leader, Tippet & Fly")->pack(qw/-side left -fill both -expand 1/);
my $ambient_fr      = $params_fr->Labelframe(-text=>"Ambient & Init")->pack(qw/-side left -fill both -expand 1/);
my $track_fr        = $params_fr->Labelframe(-text=>"Track")->pack(qw/-side left -fill both -expand 1/);
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

    $files_fr->LabEntry(-state=>'readonly',-relief=>'groove',-textvariable=>\$rps->{file}{cast},-label=>'Cast',-labelPack=>[qw/-side left/],-width=>100)->grid(-row=>3,-column=>0,-sticky=>'e');
    $files_fr->Button(-text=>'Select',-command=>sub{OnCastSelect(),-height=>'0.5'})->grid(-row=>3,-column=>1);
    $files_fr->Button(-text=>'None',-command=>sub{OnCastNone(),-height=>'0.5'})->grid(-row=>3,-column=>2);


# Set up the rod frame contents -----
    $rod_fr->LabEntry(-textvariable=>\$rps->{rod}{numNodes},-label=>'numNodes',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>0,-column=>0,-sticky=>'e');
    $rod_fr->LabEntry(-textvariable=>\$rps->{rod}{segExponent},-label=>'segExponent',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>1,-column=>0,-sticky=>'e');
    $rod_fr->LabEntry(-textvariable=>\$rps->{rod}{fiberGradient},-label=>'fiberGrad(1/in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>4,-column=>0,-sticky=>'e');
    $rod_fr->LabEntry(-textvariable=>\$rps->{rod}{maxWallThicknessIn},-label=>'maxWallThick(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>5,-column=>0,-sticky=>'e');
    $rod_fr->LabEntry(-textvariable=>\$rps->{rod}{ferruleKsMult},-label=>'ferruleKsMult',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>6,-column=>0,-sticky=>'e');
    $rod_fr->LabEntry(-textvariable=>\$rps->{rod}{vAndGMultiplier},-label=>'vAndGMult(oz/in^2)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>7,-column=>0,-sticky=>'e');
    $rod_fr->LabEntry(-textvariable=>\$rps->{rod}{densityLbFt3},-label=>'density(lb/ft3)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>8,-column=>0,-sticky=>'e');
    $rod_fr->LabEntry(-textvariable=>\$rps->{rod}{elasticModulusPSI},-label=>'elasticMod(psi)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>9,-column=>0,-sticky=>'e');
    $rod_fr->LabEntry(-textvariable=>\$rps->{rod}{dampingModulusPSI},-label=>'dampingMod(psi)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>10,-column=>0,-sticky=>'e');
    

# Set up the line_leader frame contents -----
    $line_fr->LabEntry(-textvariable=>\$rps->{line}{numNodes},-label=>'numNodes
(all components)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>0,-column=>0,-sticky=>'e');
    $line_fr->LabEntry(-textvariable=>\$rps->{line}{segExponent},-label=>'segExponent',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>1,-column=>0,-sticky=>'e');
    $line_fr->LabEntry(-textvariable=>\$rps->{line}{lenFt},-label=>'len(ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>2,-column=>0,-sticky=>'e');
    $line_fr->LabEntry(-textvariable=>\$rps->{line}{nomWtGrsPerFt},-label=>'nominalWt(gr/ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>3,-column=>0,-sticky=>'e');
    $line_fr->LabEntry(-textvariable=>\$rps->{line}{nomDiameterIn},-label=>'nomDiam(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>4,-column=>0,-sticky=>'e');
    $line_fr->LabEntry(-textvariable=>\$rps->{line}{coreDiameterIn},-label=>'coreDiam(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>5,-column=>0,-sticky=>'e');
    $line_fr->LabEntry(-textvariable=>\$rps->{line}{coreElasticModulusPSI},-label=>'coreElasticMod(psi)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>6,-column=>0,-sticky=>'e');
    $line_fr->LabEntry(-textvariable=>\$rps->{line}{dampingModulusPSI},-label=>'dampingMod(psi)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>7,-column=>0,-sticky=>'e');

# Set up the tippet_fly frame contents -----
    my @aLeaderItems = ("leader - level","leader - 7ft 5x","leader - 10ft 3x");
    $tip_fr->Optionmenu(-options=>\@aLeaderItems,-variable=>\$rps->{leader}{idx},-textvariable=>\$rps->{leader}{text},-relief=>'sunken')->grid(-row=>0,-column=>0,-sticky=>'e');
    $tip_fr->LabEntry(-textvariable=>\$rps->{leader}{lenFt},-label=>'leaderLen(ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>1,-column=>0,-sticky=>'e');
    $tip_fr->LabEntry(-textvariable=>\$rps->{leader}{wtGrsPerFt},-label=>'leaderWt(gr/ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>2,-column=>0,-sticky=>'e');
    $tip_fr->LabEntry(-textvariable=>\$rps->{leader}{diamIn},-label=>'leaderDiam(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>3,-column=>0,-sticky=>'e');
    $tip_fr->LabEntry(-textvariable=>\$rps->{leader}{coreDiamIn},-label=>'leaderCoreDiam(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>4,-column=>0,-sticky=>'e');
    my @aTippetItems = ("tippet - mono","tippet - fluoro");
    $tip_fr->Optionmenu(-options=>\@aTippetItems,-variable=>\$rps->{tippet}{idx},-textvariable=>\$rps->{line}{text},-relief=>'sunken')->grid(-row=>5,-column=>0,-sticky=>'e');
    $tip_fr->LabEntry(-textvariable=>\$rps->{tippet}{lenFt},-label=>'tippetLen(ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>6,-column=>0,-sticky=>'e');
    $tip_fr->LabEntry(-textvariable=>\$rps->{tippet}{diamIn},-label=>'tippetDiam(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>7,-column=>0,-sticky=>'e');
    $tip_fr->LabEntry(-textvariable=>\$rps->{fly}{wtGr},-label=>'flyWeight(gr)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>8,-column=>0,-sticky=>'e');
    $tip_fr->LabEntry(-textvariable=>\$rps->{fly}{nomDiamIn},-label=>'flyNomDiam(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>9,-column=>0,-sticky=>'e');
    $tip_fr->LabEntry(-textvariable=>\$rps->{fly}{nomLenIn},-label=>'flyNomLen(in)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>10,-column=>0,-sticky=>'e');


# Set up the ambient and initialization frame contents -----
    $ambient_fr->LabEntry(-textvariable=>\$rps->{ambient}{gravity},-label=>'gravity',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>0,-column=>0,-sticky=>'e');
    $ambient_fr->LabEntry(-textvariable=>\$rps->{ambient}{dragSpecsNormal},-label=>'dragSpecsNormal',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>1,-column=>0,-sticky=>'e');
    $ambient_fr->LabEntry(-textvariable=>\$rps->{ambient}{dragSpecsAxial},-label=>'dragSpecsAxial',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>2,-column=>0,-sticky=>'e');
    $ambient_fr->LabEntry(-textvariable=>\$rps->{rod}{dfltTotalTheta},-label=>'rodDfltTotalTheta',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>3,-column=>0,-sticky=>'e');
    $ambient_fr->LabEntry(-textvariable=>\$rps->{rod}{dfltDiamsMult},-label=>'rodDfltDiamsMult',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>4,-column=>0,-sticky=>'e');
    $ambient_fr->LabEntry(-textvariable=>\$rps->{line}{angle0},-label=>'lineAngle0(rad)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>5,-column=>0,-sticky=>'e');
    $ambient_fr->LabEntry(-textvariable=>\$rps->{line}{curve0},-label=>'lineCurve0(1/ft)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>6,-column=>0,-sticky=>'e');
    $ambient_fr->LabEntry(-textvariable=>\$rps->{integration}{releaseDelay},-label=>'releaseDelay',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>7,-column=>0,-sticky=>'e');
    $ambient_fr->LabEntry(-textvariable=>\$rps->{integration}{releaseDuration},-label=>'releaseDuration',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>8,-column=>0,-sticky=>'e');


# Set up the track frame contents ------
    $track_fr->LabEntry(-textvariable=>\$rps->{track}{frameRate},-label=>'frameRate(hz)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>0,-column=>0,-sticky=>'e');
    $track_fr->LabEntry(-textvariable=>\$rps->{track}{adjustEnable},-label=>'adjustEnable',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>1,-column=>0,-sticky=>'e');

    $track_fr->LabEntry(-textvariable=>\$rps->{track}{scale},-label=>'scale',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>2,-column=>0,-sticky=>'e');
    $track_fr->LabEntry(-textvariable=>\$rps->{track}{rotate},-label=>'rotate(rad)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>3,-column=>0,-sticky=>'e');
    $track_fr->LabEntry(-textvariable=>\$rps->{track}{wristTheta},-label=>'wristTheta(rad)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>4,-column=>0,-sticky=>'e');
    $track_fr->LabEntry(-textvariable=>\$rps->{track}{relRadius},-label=>'relativeROC',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>5,-column=>0,-sticky=>'e');
    $track_fr->LabEntry(-textvariable=>\$rps->{track}{driveAccelFrames},-label=>'drive,accel(fr)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>6,-column=>0,-sticky=>'e');
    $track_fr->LabEntry(-textvariable=>\$rps->{track}{delayDriftFrames},-label=>'delay,drift(fr)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>7,-column=>0,-sticky=>'e');
    $track_fr->LabEntry(-textvariable=>\$rps->{track}{driveDriftTheta},-label=>'drive,drift(rad)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>8,-column=>0,-sticky=>'e');
    $track_fr->LabEntry(-textvariable=>\$rps->{track}{boxcarFrames},-label=>'boxcar(fr)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>9,-column=>0,-sticky=>'e');



# Set up the integration frame contents -----

    $int_fr->LabEntry(-textvariable=>\$rps->{integration}{t0},-label=>'t0',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>0,-column=>0,-sticky=>'e');
    $int_fr->LabEntry(-textvariable=>\$rps->{integration}{t1},-label=>'t1',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>1,-column=>0,-sticky=>'e');
    $int_fr->LabEntry(-textvariable=>\$rps->{integration}{dt0},-label=>'dt0',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>2,-column=>0,-sticky=>'e');
    $int_fr->LabEntry(-textvariable=>\$rps->{integration}{minDt},-label=>'minDt',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>3,-column=>0,-sticky=>'e');
    $int_fr->LabEntry(-textvariable=>\$rps->{integration}{plotDt},-label=>'plotDt',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>4,-column=>0,-sticky=>'e');

    my @aStepperItems = ("msbdf_j","rk4imp_j","rk2imp_j","rk1imp_j","bsimp_j","rkf45","rk4","rk2","rkck","rk8pd","msadams");
    $int_fr->Optionmenu(-options=>\@aStepperItems,-variable=>\$rps->{integration}{stepperItem},-textvariable=>\$rps->{integration}{stepperName},-relief=>'sunken')->grid(-row=>5,-column=>0,-sticky=>'e');

    my $plotExtrasMB = $int_fr->Menubutton(-state=>'normal',-text=>'plotExtras',-relief=>'sunken',-direction=>'below',-width=>12)->grid(-row=>6,-column=>0,-sticky=>'e');
        my $plotExtrasMenu = $plotExtrasMB->Menu();
            $plotExtrasMenu->add('checkbutton',-label=>'castSplines',-variable=>\$rps->{track}{plotSplines});        
            $plotExtrasMenu->add('separator');    
            $plotExtrasMenu->add('checkbutton',-label=>'lineVXs',-variable=>\$rps->{integration}{plotLineVXs});    
            $plotExtrasMenu->add('checkbutton',-label=>'lineVYs',-variable=>\$rps->{integration}{plotLineVYs});        
            $plotExtrasMenu->add('separator');    
            $plotExtrasMenu->add('checkbutton',-label=>'lineVAs',-variable=>\$rps->{integration}{plotLineVAs});    
            $plotExtrasMenu->add('checkbutton',-label=>'lineVNs',-variable=>\$rps->{integration}{plotLineVNs});        
            $plotExtrasMenu->add('separator');    
            $plotExtrasMenu->add('checkbutton',-label=>'line_rDots',-variable=>\$rps->{integration}{plotLine_rDots});        
        $plotExtrasMB->configure(-menu=>$plotExtrasMenu);   # Attach menu to button.

    my $saveOptionsMB = $int_fr->Menubutton(-state=>'normal',-text=>'saveOptions',-relief=>'sunken',-direction=>'below',-width=>12)->grid(-row=>7,-column=>0,-sticky=>'e');
        my $saveOptionsMenu = $saveOptionsMB->Menu();
            $saveOptionsMenu->add('checkbutton',-label=>'plot',-variable=>\$rps->{integration}{savePlot});        
            $saveOptionsMenu->add('checkbutton',-label=>'data',-variable=>\$rps->{integration}{saveData});    
        $saveOptionsMB->configure(-menu=>$saveOptionsMenu);   # Attach menu to button.

    $int_fr->LabEntry(-textvariable=>\$rps->{integration}{verbose},-label=>'verbose',-validate=>'key',-validatecommand=>\&OnVerbose,-invalidcommand=>undef,-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>8,-column=>0,-sticky=>'e');


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

# Make sure required side effects of (re)setting verbose are done:
my $currentVerbose = $rps->{integration}{verbose};
$rps->{integration}{verbose} = $currentVerbose;

# Start the main event loop
MainLoop;

exit 0;
# ==============

sub HashCopy {      # Require identical structure.  No checking.
    my ($r_src,$r_target) = @_;
    
    foreach my $l0 (keys %$r_target) {
        foreach my $l1 (keys %{$r_target->{$l0}}) {
            $r_target->{$l0}{$l1} = $r_src->{$l0}{$l1};
        }
    }
}


sub OnVerbose {
    my ($propVal,$newChars,$currVal,$index,$type) = @_;
    
    ## There is difficulty which I don't see through when I try to use validatecommand and invalidcommand to change the textvariable.  For my purposes, I can use the verbose entry as in effect read only, just changing the field value from empty to 0 on saving prefs.  I got the code below online.  The elegant thing in making 'key' validation work is to allow empty as zero.
 
#print "VERBOSE CHANGED: ($propVal,$newChars,$currVal,$index,$type)\n";
    my $val = shift;
    $val ||= 0;   # Make empty numerical.
    # Get alphas and punctuation out
    if( $val !~ /^\d+$/ ){ return 0 }
    if (($val >= 0) and ($val <= 10)) {
        $verbose = $propVal;
        if ($verbose eq ''){$verbose = 0}
        $vs = ($verbose<=1 and $verbose>$tieMax)?"                                   \r":"\n";
            # Kluge city! to move any junk far to the right.  However, I also can't get \r to work correctly in TK RO, so when writing to status rather than terminal, I just newline.
        TieStatus($verbose);
#print "thisLine0 $vs nextLine0\n";     # see if \r works
        return 1;
    }
    else{ return 0 }
}

=for comment
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
=cut comment


sub TieStatus {
    my ($verbose) = @_;
    
    ## This is a bit subtle since to make 'key' work, I need to allow $verbose==''.  That will momentarily switch to status here, but nothing should be written.

    if ($verbose<=$tieMax){
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
                if (exists($src{file}{rHexCast})) {           
                    HashCopy(\%src,$rps);
                        # Need to copy so we don't break entry textvariable references.
                    $verbose = $rps->{integration}{verbose};
                    $ok = 1;
                } else {
                    print "\n File $filename is corrupted or is not an RHexCast settings file.\n";
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
            LoadRod($rps->{file}{rod});
            LoadLine($rps->{file}{line});
            LoadCast($rps->{file}{cast});
        }else{
            $rps->{file}{settings} = '';
            warn "Error:  Could not load settings from $filename.\n";
        }
    }
}

sub OnSettingsNone {
    $rps->{file}{settings} = '';
}

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

sub OnLineSelect {
    my $FSref = $mw->FileSelect(-defaultextension=>'.txt');
    $FSref->geometry('700x500');
    my $filename = $FSref->Show;
    if ($filename){
        $rps->{file}{line} = $filename;
    }
}

sub OnLineNone {
    $rps->{file}{line} = '';
}

sub OnCastSelect {
    my $FSref = $mw->FileSelect(    -filter=>'(*.txt)|(*.svg)');
    $FSref->geometry('700x500');
    my $filename = $FSref->Show;
    if ($filename){
        $rps->{file}{cast} = $filename;
    }
}

sub OnCastNone {
    $rps->{file}{cast} = '';
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
            if (!RHexCastSetup()){print "RUN ABORTED$vs"; return}
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
            
            $RHexCastRunControl{callerRunState} = 1;
            RHexCastRun();
            
        }
        case "PAUSE"        {
            print "PAUSED$vs";
            $RHexCastRunControl{callerRunState} = -1;
            $runPauseCont_btn ->configure(-text=>"CONTINUE");
        }
    }
}


sub OnStop{

    $RHexCastRunControl{callerRunState} = 0;
    $runPauseCont_btn ->configure(-text=>"RUN");
    print "STOPPED$vs";

    SetDescendants($files_fr,"-state","normal");
    SetDescendants($params_fr,"-state","normal");
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
        
        RHexCastSave($filename);
        RHexPlotExtras($filename);
    }
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
