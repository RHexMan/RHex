#!/usr/bin/perl -w

# RHexReplot3D.pl

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


## If run with one arg, the arg is taken to be the .prefs file.  Generally, when loading, file navigation will start with the exe dir, and when saving, with the directory that holds the current settings file if there is one, otherwise with the exe dir.  That will encourage outputs associated with "related" settings to settle naturally in one folder.

# ------- Startup -------------------------

my $verbose = 1;   # Not using the global.  Not user settable in this program.

use warnings;
use strict;

our $VERSION='0.01';

our $OS;
my $nargs; 
my ($exeName,$exeDir,$basename,$suffix);
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
}

use lib ($exeDir);   # This needs to be here, outside and below the BEGIN block.

use Carp;

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
use File::Spec::Functions qw ( rel2abs abs2rel splitpath );
use Scalar::Util qw(looks_like_number);

use PDL;
# Import main PDL module (see PDL.pm for equivalents).  In particular, imports PDL::Math, which redefines many POSIX math functions.  To get the original, call POSIX::aFunction.
use PDL::NiceSlice;     # Nice MATLAB-like syntax for slicing.
PDL::no_clone_skip_warning;
#* If you need to share PDL data across threads, use memory mapped data, or
#* check out PDL::Parallel::threads, available on CPAN.
#* You can silence this warning by saying `PDL::no_clone_skip_warning;'
#* before you create your first thread.


use RUtils::Print;

use RCommon qw ($inf $rSwingOutFileTag $rCastOutFileTag GetValueFromDataString GetWordFromDataString  GetQuotedStringFromDataString GetMatFromDataString Str2Vect);
use RCommonHelp qw (OnGnuplotView OnGnuplotViewCont);
use RCommonPlot3D qw ($gnuplot RCommonPlot3D);


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

my %replotParams = (file=>{},traces=>{});
    ### NOTE that after changing this structure, delete the widget prefs file.

my $rps = \%replotParams;

# BEGIN CUT & PASTE DOCUMENTATION HERE =================================================

# DESCRIPTION:  RHexReplot is a graphical interface to a utility that takes output datafiles produce by RHexCast runs and replots the data with a different choice of line and point markers and possibly reduced time range, frame rate, and plot box.  Thus, the focus of the display may be changed without the need to re-run the whole, possibly time-consuming, calculation.


# SPECIFIC DISCUSSION OF PARAMETERS, TYPICAL AND DEFAULT VALUES:

$rps->{file} = {
    rReplot    => "RHexReplot3D v1.0, 4/7/2019",  # The existence of this field is used for verification that input file is a sink settings file.  It's contents don't matter
    settings    => "SpecFiles_Preference/RHexReplot3D.prefs",
    source      => '',
    save        => '',
        # If non-empty, there is a plot to save.
};
my $defaultSettingsFile = $rps->{file}{settings};   # Save a copy.

if ($nargs>0 and $ARGV[0] ne ''){
    if ($verbose){print "Using calling argument to load settings file ".$ARGV[0]."\n"}
    $rps->{file}{settings} = $ARGV[0];
}

$rps->{traces} = {
    tStart			=> '',  # Empty for -inf, else a number
    tEnd			=> '',  # Empty for +inf, else a number
    eachText		=> 'showEach - 1',
    zScale			=> 1,
	ticksText		=> 'showTicks - no',
#	partsText		=> 'show - rod & line',
};




# Main Window
our $mw = new MainWindow;
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
    my $traces_fr  = $params_fr->Labelframe(-text=>"Traces")->pack(qw/-side left -fill both -expand 1/);

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

    $files_fr->LabEntry(-state=>'readonly',-relief=>'groove',-textvariable=>\$rps->{file}{source},-label=>'Source',-labelPack=>[qw/-side left/],-width=>100)->grid(-row=>1,-column=>0,-sticky=>'e');
    $files_fr->Button(-text=>'Select & Load',-command=>sub{OnSourceSelect(),-height=>'0.5'})->grid(-row=>1,-column=>1);


# Set up the traces frame contents -----
    $traces_fr->LabEntry(-textvariable=>\$rps->{traces}{tStart},-label=>'timeRangeStart(secs)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>0,-column=>0,-padx=>60,,-sticky=>'e');
    $traces_fr->LabEntry(-textvariable=>\$rps->{traces}{tEnd},-label=>'timeRangeEnd(secs)',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>1,-column=>0,-padx=>60,-sticky=>'e');
my @aTPlotEachItems = ("showEach - 1","showEach - 2","showEach - 3","showEach - 4","showEach - 1","showEach - 5","showEach - 10");
    $traces_fr->Optionmenu(-options=>\@aTPlotEachItems,-textvariable=>\$rps->{traces}{eachText},-relief=>'sunken',-width=>18)->grid(-row=>0,-column=>1,-padx=>60,-sticky=>'e');
my @aTicksItems = ("showTicks - no","showTicks - yes");
    $traces_fr->Optionmenu(-options=>\@aTicksItems,-textvariable=>\$rps->{traces}{ticksText},-relief=>'sunken',-width=>18)->grid(-row=>1,-column=>1,-padx=>60,-sticky=>'e');
    $traces_fr->LabEntry(-textvariable=>\$rps->{traces}{zScale},-label=>'zScale',-labelPack=>[qw/-side left/],-width=>8)->grid(-row=>0,-column=>2,-padx=>60,-sticky=>'e');
#my @aPartsItems = ("plotParts - rod & line","plotParts - rod","plotParts - line");
#    $traces_fr->Optionmenu(-options=>\@aPartsItems,-textvariable=>\$rps->{traces}{style},-relief=>'sunken')->grid(-row=>2,-column=>0,-sticky=>'e');



# Set up the run frame contents ---------

my $quit_btn  = $run_fr->Button(-text=>'Quit',-command=>sub{OnExit()}
        )->grid(-row=>3,-column=>0);
$run_fr->Button(-text=>'Save Settings',-command=>sub{OnSaveSettings()}
        )->grid(-row=>3,-column=>1);
my $plot_btn  = $run_fr->Button(-text=>'PLOT',-command=>sub{OnPlot()}
        )->grid(-row=>3,-column=>2);
$run_fr->Button(-text=>'Save Out',-command=>sub{OnSaveOut()}
        )->grid(-row=>3,-column=>3);

# Tie the print outputs to the appropriate windows:
tie *STDOUT, ref $main::status_rot, $main::status_rot;
untie *STDERR;	# Probably unnecessary.




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


sub LoadSettings {
    my ($filename) = @_;
    my $ok = 0;
    if ($filename) {
        if (-e $filename) {
            $/ = "\n";  # Avoids warning
            my $conf = Config::General->new($filename);
            my %src = $conf->getall();
            if (%src){
                if (exists($src{file}{rReplot})) {
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

	my ($dirs,$filename) = StrictRel2Abs($rps->{file}{settings},$exeDir);

    my $FSref = $mw->FileSelect(    -directory=>"$dirs",
                                    -defaultextension=>'.prefs');
    $FSref->geometry('700x500');
    $filename = $FSref->Show;
    if ($filename){
        if (LoadSettings($filename)){
            $rps->{file}{settings} = abs2rel($filename,$exeDir);
            if ($rps->{file}{source}){
                if (!LoadSource($rps->{file}{source})){$rps->{file}{source} = ''}        
            }
        }else{
            $rps->{file}{settings} = '';
            warn "Error:  Could not load settings from $filename.  Retaining previous settings file\n";
        }
    }
}


sub OnSourceSelect {

	my ($dirs,$filename) = StrictRel2Abs($rps->{file}{source},$exeDir);

    my $FSref = $mw->FileSelect(    -directory=>"$dirs",
                                    -filter=>'(*.txt)');
    $FSref->geometry('700x500');        
    $filename = $FSref->Show;
    if ($filename){
		$filename = abs2rel($filename,$exeDir);
        $rps->{file}{source} = LoadSource($filename) ? $filename : '';
    }
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


my ($Ts,$Xs,$Ys,$Zs,$plotTitleStr);
my ($XLineTips,$YLineTips,$ZLineTips,$XLeaderTips,$YLeaderTips,$ZLeaderTips);
my %opts;

sub OnPlot{

	print "PLOTTING  ";

    if ($rps->{file}{source} eq ''){
        warn "- ERROR:  Nothing to plot.\n";
        return;
    }

    $plotTitleStr = "RHexReplot - ".$inRunIdentifier;
	#pq $inTs;


    my ($it0,$it1)  = (0,($inTs->nelem)-1);
	
    my $iDelta	= substr($rps->{traces}{eachText},11);
	#pq($it0,$it1,$iDelta);

    if ($inTs->nelem > 1){
    
        #my $tr = Str2Vect($rps->{traces}{timeRange});
		my $t0 = $rps->{traces}{tStart};
		if ($t0 eq ""){$t0 = -$inf}
		elsif (!looks_like_number($t0)){print "- ERROR: plotStartTime must be empty or a number"; return}
		
		my $t1 = $rps->{traces}{tEnd};
		if ($t1 eq ""){$t1 = $inf}
		elsif (!looks_like_number($t0)){print "- ERROR: plotEndTime must be empty or a number\n"; return}
		
		if ($t0>$t1){print "- ERROR:  Lower time range bound must be less than or equal to the upper.\n"; return}

		# Set time range:
			
		my $its = which($inTs>=$t0);
		if ($its->isempty){
			warn "- ERROR:  No loaded trace times in plot range.\n";
			return;
		}
		if ($its(0)>$it0){$it0=$its(0)}
		
		$its = which($inTs<=$t1);
		if ($its->isempty){
			warn "- ERROR:  No loaded trace times in plot range.\n";
			return;
		}
		if ($its(-1)<$it1){$it1=$its(-1)}
		
		#pq($it0,$it1);
		#pq($inTs);
		
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

	my $zScale = $rps->{traces}{zScale};
	if ($zScale eq "" or !looks_like_number($zScale) or $zScale<1 or $zScale>5){print "- ERROR: zScale must be a number in the range [1,5]\n"; return}

    my $ticksStr	= substr($rps->{traces}{ticksText},12);
	#pq($ticksStr);
	my $showTicks = ($ticksStr eq "yes")?1:0;
	#pq($showTicks);

    %opts = (	gnuplot		=> $gnuplot,
				ZScale      => $zScale,
                RodTicks    => $showTicks,
                LineTicks   => $showTicks  );

    RCommonPlot3D("window",'',$plotTitleStr,$inParamsStr,
                    $Ts,$Xs,$Ys,$Zs,$XLineTips,$YLineTips,$ZLineTips,$XLeaderTips,$YLeaderTips,$ZLeaderTips,$numRodNodes,$plotBottom,'',1,\%opts);
	
	print "- OK\n";
}



sub GetItemVal {
    my($str) = @_;

    $str =~ m[.*\((\d*?)\)];
#print "str=$str,val=$1\n";
    return $1;
}



sub OnSaveOut{


    if ($rps->{file}{source} eq ''){
        print "Nothing to save.\n";
        return;
    }
	
	# Build the save filename from the current source:
	my $filename = $rps->{file}{source};
    $filename = fileparse($rps->{file}{source},'.txt');
    $filename = "_".$filename."_Replot";
	
	# Start navigating where the last save was located:
	my $dirs;
	my $saveFilename =  $rps->{file}{save};
	if ($saveFilename){
		my ($volume,$tDirs,$file) = splitpath($saveFilename);
		$dirs = rel2abs($tDirs,$exeDir);		}
	else {$dirs = $exeDir}
	
    $filename = $mw->getSaveFile(   -defaultextension=>'',
                                    -initialfile=>"$filename",
                                    -initialdir=>"$dirs");
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
	 ['command', 'About', -command=>[\&OnAbout]],
	 ['command', 'License', -command=>[\&OnLicense]],
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
RHexReplot3D 0.01, by Rich Miller, 2019

A utility for replotting output data files produced by RHexSwing3D and RHexCast3D runs.
Allows replotting with reduced time range and frame rate.  Thus, some details of the
display may be changed without the need to re-run a whole calculation.

Settings can be saved and reloaded.  Select and load the data source from a .txt file
previously saved in RHexSwing3D or RHexCast3D.  Once a source is loaded, you can press
the plot button to draw the plot.  Once you have replotted plotted, save out produces a
.eps file holding a fixed 2D projection of the 3D plot.

timeRangeStart - A number denoting seconds.  Plots only original traces whose times are
greater than or equal to this number.

timeRangeEnd - A number denoting seconds.  Plots only original traces whose times are
less than or equal to this number.

showEach - An integer number. Prints only the subset of the traces whose original index
was evenly divisible by this number.

showTicks - Show tick marks at the segment boundaries.

zScale - A positive number in the range [1,5] that sets the vertical scale magnification
relative to the fixed (and equal) X and Y scales.
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
RHexReplot3D 0.01
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

#evaluates code in the entry text pane
sub OnEval{
}

__END__

=head1 NAME

RHexReplot3D - A PERL program that replots output data files saved during RHexSwing3D and RHexCast3D runs.


=head1 SYNOPSIS

Enter perl RHexReplot3D.pl in a terminal window, or double-click on the shell script RHexReplot3D.sh in the finder window, or run the stand-alone executable RHexReplot3D if it is available.
  
=head1 DESCRIPTION

A utility for replotting output data files produced by RHexSwing3D and RHexCast3D runs.  Allows replotting with  reduced time range and frame rate.  Thus, some details of the display may be changed without the need to re-run a whole calculation.

Settings can be saved and reloaded.  Select and load the data source from a .txt file previously saved in RHexSwing3D or RHexCast3D.  Once a source is loaded, you can press the plot button to draw the plot.  Once you have replotted plotted, save out produces a .eps file holding a fixed 2D projection of the 3D plot.

timeRangeStart - A number denoting seconds.  Plots only original traces whose times are greater than or equal to this number.

timeRangeEnd - A number denoting seconds.  Plots only original traces whose times are less than or equal to this number.

showEach - An integer number. Prints only the subset of the traces whose original index was evenly divisible by this number.

showTicks - Show tick marks at the segment boundaries.

zScale - A positive number in the range [1,5] that sets the vertical scale magnification relative to the fixed (and equal) X and Y scales.

=head1 A USEFUL NOTE

As with the swinging and casting programs, plots here persist while the program is running. To unclutter, rather than manually closing each, first save your parameters, and then just close the Terminal window that appeared when this program was launched.  That will cause all the plots to disappear.  Then simply relaunch this program.  Because you have saved the parameters, the new launch will start where the old one left off.

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





