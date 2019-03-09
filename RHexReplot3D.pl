#!/usr/bin/perl -w

## If run with one arg, it is taken to be the .prefs file.  Generally, when loading, file navigation will start with the exe dir, and when saving, with the directory that holds the current settings file if there is one, otherwise with the exe dir.  That will encourage outputs associated with "related" settings to settle naturally in one folder.

## However, for this script, the "source" directory also wants to be the settings dir, since that source will be output from RHexCast.

# ------- Startup -------------------------

my $verbose = 1;

chomp(my $exeName = `echo $0`); 
    # Gets rid of the trailing newline with which shell commands finish.
chomp(my $exeDir  = `dirname $0`);
#print "exeDir = $exeDir\n";
chdir "$exeDir";  # See perldoc -f chdir
#`cd $exeDir`;   # This doesn't work, but the perl function chdir does!
chomp($exeDir = `pwd`);  # Force full pathname.
if ($verbose){print "Running $exeName @ARGV, working in $exeDir.\n"}

my $nargs = @ARGV;
if ($nargs>1){die "\n$0: Usage:RHexReplot.pl [settingsFile]\n"} 

# --------------------------------

use warnings;
use strict;

use utf8;   # To help pp, which couldn't find it in require in AUTOLOAD.  This worked!

#use Tk 800.000;     # Surprise.  It works even in my Perl-5.12.5 which downloaded a newer ver.
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
use Switch;
use Try::Tiny;
use File::Basename;

use PDL;
# Import main PDL module (see PDL.pm for equivalents).  In particular, imports PDL::Math, which redefines many POSIX math functions.  To get the original, call POSIX::aFunction.
use PDL::NiceSlice;     # Nice MATLAB-like syntax for slicing.

use RPrint;
use RCommon qw ($rSwingOutFileTag $rCastOutFileTag GetValueFromDataString GetWordFromDataString  GetQuotedStringFromDataString GetMatFromDataString Str2Vect);

use RCommonPlot3D qw (RCommonPlot3D);



my %replotParams = (file=>{},trace=>{},rod=>{},line=>{});
    ### NOTE that after changing this structure, delete the widget prefs file.

my $rps = \%replotParams;

# BEGIN CUT & PASTE DOCUMENTATION HERE =================================================

# DESCRIPTION:  RHexReplot is a graphical interface to a utility that takes output datafiles produce by RHexCast runs and replots the data with a different choice of line and point markers and possibly reduced time range, frame rate, and plot box.  Thus, the focus of the display may be changed without the need to re-run the whole, possibly time-consuming, calculation.


# SPECIFIC DISCUSSION OF PARAMETERS, TYPICAL AND DEFAULT VALUES:

$rps->{file} = {
    rHexReplot    => "RHexReplot 1.1, 2/17/2019",
        # Used for verification that input file is a replot settings file.
    settings    => "RHexReplot3D.prefs",
    source      => '',
    save        => '',
        # If non-empty, there is a plot to save.
};
my $defaultSettingsFile = $rps->{file}{settings};   # Save a copy.

if ($nargs>0 and $ARGV[0] ne ''){
    if ($verbose){print "Using calling argument to load settings file ".$ARGV[0]."\n"}
    $rps->{file}{settings} = $ARGV[0];
}

$rps->{trace} = {
    style           => "trace - overlay",
    plotEach        => 1,
    timeRange       => '',  # Empty for all, else "num1,num2".
    plotZScale      => 1,
};

$rps->{rod} = {
    strokeType      => "stroke - solid(1)",
    tipType         => 6,   # dot-circle
    handleType      => 1,   # plus sign
    showTicks       => 0,
};

$rps->{line} = {
    showLine    => 1,   # Zero suppresses line plotting
    strokeType  => 2,   # long dash
    tipType     => 12,  # dot-diamond
    showTicks   => 0,
};

# END CUT & PASTE DOCUMENTATION HERE =================================================


# Main Window
my $mw = new MainWindow;
$mw->geometry('1000x400+150+0');
$mw->resizable(0,0);

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

my $params_fr    = $mw->Frame->pack(qw/-side top -fill both -expand 1/);
    my $traceParams_fr  = $params_fr->Labelframe(-text=>"Trace")->pack(qw/-side left -fill both -expand 1/);
    my $rodParams_fr    = $params_fr->Labelframe(-text=>"Rod")->pack(qw/-side left -fill both -expand 1/);
    my $lineParams_fr   = $params_fr->Labelframe(-text=>"Line")->pack(qw/-side left -fill both -expand 1/);

my $run_fr       = $mw->Labelframe(-text=>"Execution")->pack(qw/-side bottom -fill both -expand 1/);


# Set up the files frame contents -----
    $files_fr->LabEntry(-state=>'readonly',-relief=>'groove',-textvariable=>\$rps->{file}{settings},-label=>'Settings',-labelPack=>[qw/-side left/],-width=>100)->grid(-row=>0,-column=>0,-sticky=>'e');
    $files_fr->Button(-text=>'Select & Load',-command=>sub{OnSettingsSelect(),-height=>'0.5'})->grid(-row=>0,-column=>1);

    $files_fr->LabEntry(-state=>'readonly',-relief=>'groove',-textvariable=>\$rps->{file}{source},-label=>'Source',-labelPack=>[qw/-side left/],-width=>100)->grid(-row=>1,-column=>0,-sticky=>'e');
    $files_fr->Button(-text=>'Select & Load',-command=>sub{OnSourceSelect(),-height=>'0.5'})->grid(-row=>1,-column=>1);


# Set up the trace frame contents -----
my @aTraceStyleItems = ("style - overlay");
    $traceParams_fr->Optionmenu(-options=>\@aTraceStyleItems,-textvariable=>\$rps->{trace}{style},-relief=>'sunken')->grid(-row=>0,-column=>0,-sticky=>'e');
    $traceParams_fr->LabEntry(-textvariable=>\$rps->{trace}{plotEach},-label=>'plotEach',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>1,-column=>0,-sticky=>'e');
    $traceParams_fr->LabEntry(-textvariable=>\$rps->{trace}{timeRange},-label=>'timeRange(secs)',-labelPack=>[qw/-side left/],-width=>16)->grid(-row=>2,-column=>0,-sticky=>'e');
    $traceParams_fr->LabEntry(-textvariable=>\$rps->{trace}{plotZScale},-label=>'plotZScale',-labelPack=>[qw/-side left/],-width=>16)->grid(-row=>3,-column=>0,-sticky=>'e');
    

#	# Indexed line type of postscript terminal of gnuplot
#	my %type = (
#		solid          => 1,
#		longdash       => 2,
#		dash           => 3,
#		dot            => 4,
#		'dot-longdash' => 5,
#		'dot-dash'     => 6,
#		'2dash'        => 7,
#		'2dot-dash'    => 8,
#		'4dash'        => 9,
#	);

#	# Indexed line type of postscript terminal of gnuplot
#	my %type = (
#		dot               => 0,
#		plus              => 1,
#		cross             => 2,
#		star              => 3,
#		'dot-square'      => 4,
#		'dot-circle'      => 6,
#		'dot-triangle'    => 8,
#		'dot-diamond'     => 12,
#		'dot-pentagon'    => 14,
#		'fill-square'     => 5,
#		'fill-circle'     => 7,
#		'fill-triangle'   => 9,
#		'fill-diamond'    => 13,
#		'fill-pentagon'   => 15,
#		square            => 64,
#		circle            => 65,
#		triangle          => 66,
#		diamond           => 68,
#		pentagon          => 69,
#		'opaque-square'   => 70,
#		'opaque-circle'   => 71,
#		'opaque-triangle' => 72,
#		'opaque-diamond'  => 74,
#		'opaque-pentagon' => 75,
#	);


my @aStrokeItems    = ("stroke - solid(1)","stroke - longdash(2)");
my @aRodTipItems    = ("tip - dot(0)","tip - plus(1)","tip - dot-circle(6)","tip - fill-circle(7)");
my @aRodHandleItems = ("handle - dot(0)","handle - plus(1)");

# Set up the rod frame contents -----
    $rodParams_fr->Optionmenu(-options=>\@aStrokeItems,-textvariable=>\$rps->{rod}{strokeType},-relief=>'sunken')->grid(-row=>0,-column=>0,-sticky=>'e');
    $rodParams_fr->Optionmenu(-options=>\@aRodTipItems,-textvariable=>\$rps->{rod}{tipType},-relief=>'sunken')->grid(-row=>1,-column=>0,-sticky=>'e');
    $rodParams_fr->Optionmenu(-options=>\@aRodHandleItems,-textvariable=>\$rps->{rod}{handleType},-relief=>'sunken')->grid(-row=>2,-column=>0,-sticky=>'e');
    $rodParams_fr->LabEntry(-textvariable=>\$rps->{rod}{showTicks},-label=>'showTicks',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>3,-column=>0,-sticky=>'e');


my @aLineTipItems = ("tip - dot(0)","tip - plus(1)","tip - dot-diamond(12)","tip - fill-diamond(13)");

    $lineParams_fr->LabEntry(-textvariable=>\$rps->{line}{showLine},-label=>'showLine',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>0,-column=>0,-sticky=>'e');
    $lineParams_fr->Optionmenu(-options=>\@aStrokeItems,-textvariable=>\$rps->{line}{strokeType},-relief=>'sunken')->grid(-row=>1,-column=>0,-sticky=>'e');
    $lineParams_fr->Optionmenu(-options=>\@aLineTipItems,-textvariable=>\$rps->{line}{tipType},-relief=>'sunken')->grid(-row=>2,-column=>0,-sticky=>'e');
    $lineParams_fr->LabEntry(-textvariable=>\$rps->{line}{showTicks},-label=>'showTicks',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>3,-column=>0,-sticky=>'e');


# Set up the run frame contents ---------

my $quit_btn  = $run_fr->Button(-text=>'Quit',-command=>sub{OnExit()}
        )->grid(-row=>0,-column=>0);
$run_fr->Button(-text=>'Save Settings',-command=>sub{OnSaveSettings()}
        )->grid(-row=>0,-column=>1);
my $plot_btn  = $run_fr->Button(-text=>'PLOT',-command=>sub{OnPlot()}
        )->grid(-row=>0,-column=>2);
$run_fr->Button(-text=>'Save Out',-command=>sub{OnSaveOut()}
        )->grid(-row=>0,-column=>3);

$run_fr->Label(-text=>" ",-width=>'120')->grid(-row=>1,-column=>0,-columnspan=>4);       
        

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
    $filename = '';
    warn "Unable to find good setings file, using built-in settings.\n\n";
}
$rps->{file}{settings} = $filename;

# If there is a source file, try to load it:
$filename = $rps->{file}{source};
if ($filename){$rps->{file}{source} = LoadSource($filename) ? $filename : ''}


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

sub LoadSettings {
    my ($filename) = @_;
    my $ok = 0;
    if ($filename) {
        if (-e $filename) {
            $/ = "\n";  # Avoids warning
            my $conf = Config::General->new($filename);
            my %src = $conf->getall();
            if (%src){
                if (exists($src{file}{rHexReplot})) {           
                    HashCopy(\%src,$rps);
                        # Need to copy so we don't break entry textvariable references.
                    $ok = 1;
                } else {
                    print "\n File $filename is corrupted or is not an RHexReplot settings file.\n";
                }
            }
        }
    }    
    return $ok;
}


my ($inParamsStr,$numRodNodes,$inTs,$inXs,$inYs,$inZs,$inXLineTips,$inYLineTips,$inZLineTips,$inXLeaderTips,$inYLeaderTips,$inZLeaderTips,$plotBottom);

my $inRunIdentifier;

sub LoadSource {
    my ($filename) = @_;
    
    if ($verbose>=1){print "Loading simulation data from $filename.\n"}        

    my $ok = 0;
    if ($filename){
        if (-e $filename) {

            $ok = 1;
            my ($nrows,$ncols);

            $/ = undef;
            open INFILE, "< $filename" or $ok = 0;
            if (!$ok){warn $!;return 0}
            my $inData = <INFILE>;
            close INFILE;
            
            if (!($inData =~ /$rSwingOutFileTag/)){  # later, also cast.
                warn "Error: $filename is not a recognized output file.\n";
                return 0;
            }
            
            if ($verbose>=2){pq $inData}
            my $eh = "Error:  Could not load plot data from $filename - ";
            my $et = "data not found or corrupted.\n";
            
            $inParamsStr = GetQuotedStringFromDataString($inData,"ParamsString");
            if ($inParamsStr eq '')
                {warn "$eh ParamsString $et";return 0};

            $numRodNodes = GetValueFromDataString($inData,"NumRodNodes");
            if ($numRodNodes eq '')
                {warn "$eh NumRodNodes $et";return 0};

            $inTs = GetMatFromDataString($inData,"PlotTs");
#pq $inTs;
            my ($nTimes,$unused) = $inTs->dims;    
            if ($nTimes == 0 or defined($unused))
                {warn "$eh PlotTs $et"; return 0};

            $inXs = GetMatFromDataString($inData,"PlotXs");            
#pq $inXs;
            my ($nNodesX,$nTimesX) = $inXs->dims;
            if (!defined($nTimesX)){$nTimesX = 1}   
            if ($nNodesX == 0 or $nTimesX != $nTimes)
                {warn "$eh PlotXs $et"; return 0};

            $inYs = GetMatFromDataString($inData,"PlotYs");
            my ($nNodesY,$nTimesY) = $inYs->dims;
            if (!defined($nTimesY)){$nTimesY = 1}
            #pq $inYs;
            if ($nNodesY != $nNodesX or $nTimesY != $nTimes)
            {warn "$eh PlotYs $et"; return 0};
            if ($numRodNodes > $nNodesX)
            {warn "$eh detected bad inNumRodNodes.\n"; return 0};
            
            $inZs = GetMatFromDataString($inData,"PlotZs");
            my ($nNodesZ,$nTimesZ) = $inZs->dims;
            if (!defined($nTimesZ)){$nTimesZ = 1}
            #pq $inZs;
            if ($nNodesZ != $nNodesX or $nTimesZ != $nTimes)
            {warn "$eh PlotZs $et"; return 0};
            if ($numRodNodes > $nNodesZ)
            {warn "$eh detected bad inNumRodNodes.\n"; return 0};
            
            
            $inXLineTips = GetMatFromDataString($inData,"PlotXLineTips");
            ($ncols,$nrows) = $inXLineTips->dims;
            if ($ncols != 1 or $nrows != $nTimes)
            {warn "$eh PlotXLineTips $et"; return 0};
            
            $inYLineTips = GetMatFromDataString($inData,"PlotYLineTips");
            ($ncols,$nrows) = $inYLineTips->dims;
            if ($ncols != 1 or $nrows != $nTimes)
            {warn "$eh PlotYLineTips $et"; return 0};
            
            $inZLineTips = GetMatFromDataString($inData,"PlotZLineTips");
            ($ncols,$nrows) = $inZLineTips->dims;
            if ($ncols != 1 or $nrows != $nTimes)
            {warn "$eh PlotZLineTips $et"; return 0};
            
            $inXLeaderTips = GetMatFromDataString($inData,"PlotXLeaderTips");
            ($ncols,$nrows) = $inXLeaderTips->dims;
            if ($ncols != 1 or $nrows != $nTimes)
            {warn "$eh PlotXLeaderTips $et"; return 0};
            
            $inYLeaderTips = GetMatFromDataString($inData,"PlotYLeaderTips");
            ($ncols,$nrows) = $inYLeaderTips->dims;
            if ($ncols != 1 or $nrows != $nTimes)
            {warn "$eh PlotYLeaderTips $et"; return 0};
            
            $inZLeaderTips = GetMatFromDataString($inData,"PlotZLeaderTips");
            ($ncols,$nrows) = $inZLeaderTips->dims;
            if ($ncols != 1 or $nrows != $nTimes)
            {warn "$eh PlotZLeaderTips $et"; return 0};
            
            $plotBottom = GetValueFromDataString($inData,"PlotBottom");
            if ($plotBottom eq '')
            {warn "$eh PlotBottom $et";return 0};
            
            #pq($inXLineTips,$inYLineTips,$inZLineTips,$inXLeaderTips,$inYLeaderTips,$inZLeaderTips);

            $inRunIdentifier = GetWordFromDataString($inData,"RunIdentifier");
            #pq($inRunIdentifier);
            if (!defined($inRunIdentifier))
               {warn "$eh RunIdentifier $et";return 0};

        }else{ warn "Could not find $filename\n"}
    }
    return $ok;
}





my @types = (["Config Files", '.prefs', 'TEXT'],
       ["All Files", "*"] );

sub OnSettingsSelect {
    my $settingsDir = dirname($rps->{file}{settings});
    my $FSref = $mw->FileSelect(    -directory=>"$settingsDir",
                                    -defaultextension=>'.prefs');
    $FSref->geometry('700x500');
    my $filename = $FSref->Show;
    if ($filename){
        if (LoadSettings($filename)){
            $rps->{file}{settings} = $filename;
            if ($rps->{file}{source}){
                if (!LoadSource($rps->{file}{source})){$rps->{file}{source} = ''}        
            }
        }else{
            $rps->{file}{settings} = '';
            warn "Error:  Could not load settings from $filename.\n";
        }
    }
}


sub OnSourceSelect {
    my $settingsDir = dirname($rps->{file}{settings});
    my $FSref = $mw->FileSelect(    -directory=>"$settingsDir",
                                    -filter=>'(*.txt)');
    $FSref->geometry('700x500');        
    my $filename = $FSref->Show;
    if ($filename){
        $rps->{file}{source} = LoadSource($filename) ? $filename : '';
    }
}


sub OnSaveSettings{
    my $filename = $rps->{file}{settings};
    my ($basename,$dirs,$suffix) = fileparse($filename,'.prefs');
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


my ($Ts,$Xs,$Ys,$Zs,$plotTitleStr);
my ($XLineTips,$YLineTips,$ZLineTips,$XLeaderTips,$YLeaderTips,$ZLeaderTips);
my %opts;

sub OnPlot{

#print "PLOT BUTTON PRESSED.\n";

    if ($rps->{file}{source} eq ''){
        warn "ERROR:  Nothing to plot.\n";
        return;
    }

    $plotTitleStr = "RHexReplot - ".$inRunIdentifier;

#pq $inTs;
#pq $plotTs;

    my ($it0,$it1)  = (0,($inTs->nelem)-1);
    my $iDelta      = $rps->{trace}{plotEach};

    if ($inTs->nelem > 1){
    
        my $tr = Str2Vect($rps->{trace}{timeRange});
        if ($tr->nelem){
             # Set time range and possibly skip traces:

            my $deltaT  = $inTs(1)-$inTs(0);
            if ($tr->nelem == 1){
                # If only one number, not zero, use it as the lower time bound:
                $tr = min($tr,$inTs(-1));
                $tr = pdl($tr);
                $tr = $tr->glue(0,$inTs(-1)+$deltaT);
                    # Make sure we get the last index.
            }

            my $maxITs   = ($inTs->nelem)-1;

            $it0     = ceil($tr(0)/$deltaT)->sclr;
            $it1     = floor($tr(1)/$deltaT)->sclr;
            
            $it0 = ($it0<0)?0:$it0;
            $it0 = ($it0>$maxITs)?$maxITs:$it0;
            
            $it1 = ($it1<$it0)?$it0:$it1;
            $it1 = ($it1>$maxITs)?$maxITs:$it1;
        }
        
        $plotTitleStr .= sprintf(" (%.3f,%.3f)",$inTs($it0)->sclr,$inTs($it1)->sclr);
#        $plotTitleStr .= ' ('.$inTs($it0).','.$inTs($it1).')';
           # Want to show actual time range in title.
    }

    $Ts = $inTs($it0:$it1:$iDelta);
    $Xs = $inXs(:,$it0:$it1:$iDelta);
    $Ys = $inYs(:,$it0:$it1:$iDelta);
    $Zs = $inZs(:,$it0:$it1:$iDelta);
    
    #pq($inXLineTips,$inYLineTips,$inZLineTips,$inXLeaderTips,$inYLeaderTips,$inZLeaderTips);
    
    $XLineTips      = $inXLineTips(:,$it0:$it1:$iDelta);
    $YLineTips      = $inYLineTips(:,$it0:$it1:$iDelta);
    $ZLineTips      = $inZLineTips(:,$it0:$it1:$iDelta);
    $XLeaderTips    = $inXLeaderTips(:,$it0:$it1:$iDelta);
    $YLeaderTips    = $inYLeaderTips(:,$it0:$it1:$iDelta);
    $ZLeaderTips    = $inZLeaderTips(:,$it0:$it1:$iDelta);
    
    
    #pq($XLineTips,$YLineTips,$ZLineTips,$XLeaderTips,$YLeaderTips,$ZLeaderTips);


    %opts = (   ZScale      => $rps->{trace}{plotZScale},
                RodStroke   => GetItemVal($rps->{rod}{strokeType}),
                RodTip      => GetItemVal($rps->{rod}{tipType}),
                RodHandle   => GetItemVal($rps->{rod}{handleType}),
                RodTicks    => $rps->{rod}{showTicks},
                ShowLine    => $rps->{line}{showLine},
                LineStroke  => GetItemVal($rps->{line}{strokeType}),
                LineTip     => GetItemVal($rps->{line}{tipType}),
                LineTicks   => $rps->{line}{showTicks}  );



    RCommonPlot3D("window",'',$plotTitleStr,$inParamsStr,
                    $Ts,$Xs,$Ys,$Zs,$XLineTips,$YLineTips,$ZLineTips,$XLeaderTips,$YLeaderTips,$ZLeaderTips,$numRodNodes,$plotBottom,'',1,\%opts);
}



sub GetItemVal {
    my($str) = @_;

    $str =~ m[.*\((\d*?)\)];
#print "str=$str,val=$1\n";
    return $1;
}



sub OnSaveOut{

#print "SAVE OUT pressed.\n";

    if ($rps->{file}{source} eq ''){
        print "Nothing to save.\n";
        return;
    }
    
    my $filename = $rps->{file}{source};
    my($basename,$dirs,$suffix) = fileparse($filename,'.txt');
    $basename = "_".$basename."_Replot";
    my $settingsDir = dirname($rps->{file}{settings});
    $filename = $mw->getSaveFile(   -defaultextension=>'',
                                    -initialfile=>"$basename",
                                    -initialdir=>"$settingsDir");                                    
    if ($filename) {    

        my $titleStr = $plotTitleStr."(Mod)";        
        RCommonPlot3D("file",$filename,$plotTitleStr,$inParamsStr,
                    $Ts,$Xs,$Ys,$Zs,$XLineTips,$YLineTips,$ZLineTips,$XLeaderTips,$YLeaderTips,$ZLeaderTips,$numRodNodes,$plotBottom,'',1,\%opts);
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
# 	 [qw/cascade Operations -tearoff 0 -menuitems/ =>
# 	  [
# 	   [qw/command ~Open  -accelerator Ctrl-o/,
# 	    -command=>[\&OnFileOpen]],
# 	   [qw/command ~Save  -accelerator Ctrl-s/,
# 	    -command=>[\&OnFileSave]],
# 	   ]
# 	 ],
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
		   -title=>"About Jack",
		   -buttons=>["OK"]
		   );

    # Now we need to add a Label widget so we can show some text.  The
    # DialogBox is essentially an empty frame with no widgets in it.
    # You can images, buttons, text widgets, listboxes, etc.
    $about->add('Label',
		-anchor=>'w',
		-justify=>'left',
		-text=>qq(
RHexReplot 1.1, by Rich Miller, 2015

A utility for replotting output datafiles produced by RHexCast runs
with a different choice of line and point markers and possibly reduced
time range, frame rate, and plot box.  Thus, the focus of the display
may be changed without the need to re-run the whole, possibly
time-consuming, calculation.
)
		)->pack;

    $about->Show();
}


#evaluates code in the entry text pane
sub OnEval{
}


