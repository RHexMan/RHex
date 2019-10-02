#!/usr/bin/perl -w

# RCommonInterface.pm

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

package RCommonInterface;

## All the common handling code for the control panels.

use warnings;
use strict;

our $VERSION='0.01';

#our $mw;

use RCommonHelp;
use RCommon qw (DEBUG $verbose $restoreVerbose $debugVerbose $periodicVerbose %runControl $vs);

# Make $rps and the exported functions available:
use if $main::program eq "RSwing3D", "RSwing3D", ;		# perldoc if
use if $main::program eq "RCast3D", "RCast3D", ;

use Exporter 'import';
our @EXPORT = qw(HashCopy StrictRel2Abs OnVerbose OnDebugVerbose ChangeVerbose OnPeriodicVerbose SetTie LoadSettings OnSettingsSelect OnSettingsNone OnRodSelect OnRodNone OnLineSelect OnLineNone OnLeaderSelect OnLeaderNone OnDriverSelect OnDriverNone OnSaveSettings OnRunPauseCont OnStop OnSaveOut SetOneField SetFields SetDescendants OnLineEtc OnVerboseParam OnGnuplotView OnGnuplotViewCont);

use Carp;

use utf8;   # To help pp, which couldn't find it in require in AUTOLOAD.  This worked!

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

# Variable Defs ==========
#our $mw;

my $tieMax = 2;
    # Values of verbose greater than this cause stdout and stderr to go to the terminal window, smaller values print to the widget's status window.  Set to -1 for serious debugging.


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

	## Deal with the verbose menu and its side effects.
	#carp "I am in OnVerbose, called \n";
	
	# Strangely, Tk::Optionmenu when set up with the (["verbose - 0"=>0],["verbose - 1"=>1],...) form of item list, does not seem to keep the -variable and -textvariable synched if you set one or the other from the linked variable.  Indeed, if you reset the one linked to -textvariable, the menu visibly changes, but not if you reset the one linked to -variable.  However, if you change the menu item from the widget, then both linked variables change appropriately.
	
	# So, it's not worth messing with the item number. I just convert the string and implement the side effects I want.
	
	my $name = $rps->{integration}{verboseName};
	#print "\$name=$name\n";
	$verbose = substr($name,10);
	#print "\$verbose=$verbose\n";
	
	$vs = ($verbose<=1 and $verbose>$tieMax)?"                                   \r":"\n";
		# Kluge city! to move any junk far to the right.  However, I also can't get \r to work correctly in TK RO, so when writing to status rather than terminal, I just newline.
	#croak "Where am I/\n";
	#SetTie(3);
	SetTie($verbose);
	$restoreVerbose = $verbose;
		# DE() in RHamilton3D can change $verbose temporarily, and the verbose switch mechanism there needs to know what to come back to.
}


sub OnDebugVerbose {


	## The menu handler doesn't give back an item number, only the menu item labels, so I need to convert to a number. See comment in OnVerbose().
	
	#carp "I am in OnDebugVerbose, called \n";

	my $name = $rps->{integration}{debugVerboseName};
	#print "\$name=$name\n";
	$debugVerbose = substr($name,15);
}

sub OnPeriodicVerbose {

	$periodicVerbose = $rps->{integration}{switchEachPlotDt};
}

=begin comment

sub OnVerbose {
    my ($propVal,$newChars,$currVal,$index,$type) = @_;
    
    ## There is difficulty which I don't see through when I try to use validatecommand and invalidcommand to change the textvariable.  For my purposes, I can use the verbose entry as in effect read only, just changing the field value from empty to 0 on saving prefs.  I got the code below online.  The elegant thing in making 'key' validation work is to allow empty as zero.
	
	
	# http://infohost.nmt.edu/tcc/help/pubs/tkinter/web/entry-validation.html
 
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
		$restoreVerbose = $verbose;
			# DE() in RHamilton3D can change $verbose temporarily, and the verbose switch mechanism there needs to know what to come back to.
		
        return 1;
    }
	else{ return 0 }
}


## NB. This is called if the validatecommand function returns invalid.  I should be able to use this to reset  - our problem seems to be that before inserting a deletion is done, and that goes to the validate ftn.


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
	
	## To be called only by the verbose switching mechanism.
	
    #print "Entering ChangeVerbose: verbose=$verbose,newVerbose=$newVerbose\n";
	my $saveRestoreVerbose = $restoreVerbose;
	
    $rps->{integration}{verboseName} = "verbose - ".$newVerbose;
    #pq($newVerbose);die;
    OnVerbose();
    #print "Exiting ChangeVerbose:  verbose=$verbose\n";
	
	# Undo OnVerbose()'s change of restore verbose:
	$restoreVerbose = $saveRestoreVerbose;
}


sub SetTie {
    my ($verbose) = @_;
    
    ## This is a bit subtle since to make 'key' work, I need to allow $verbose==''.  That will momentarily switch to status here, but nothing should be written.

    if ($verbose eq ''){die "\nASTONISHED THAT I AM CALLED.\n\nStopped"}   # Noop.
    
    elsif ($verbose<=$tieMax){
        tie *STDOUT, ref $main::status_rot, $main::status_rot;
        tie *STDERR, ref $main::status_rot, $main::status_rot;
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
				my $tStr = ($main::program eq "RCast3D") ? "rCast" : "rSwing";
                if (exists($src{file}{$tStr})) {
                    HashCopy(\%src,$rps);
                        # Need to copy so we don't break entry textvariable references.
					OnVerbose();
                    #$verbose = $rps->{integration}{verbose};
                    $ok = 1;
                } else {
                    print "\n File $filename is corrupted or is not an $tStr settings file.\n";
                }
            }
        }
    }
    return $ok;
}



my @types = (["Config Files", '.prefs', 'TEXT'],
       ["All Files", "*"] );


sub OnSettingsSelect {

	my ($dirs,$filename) = StrictRel2Abs($rps->{file}{settings},$main::exeDir);

    my $FSref = $main::mw->FileSelect(-directory=>$dirs,-defaultextension=>'.prefs');
    $FSref->geometry('700x500');
    $filename = $FSref->Show;
	
    if ($filename){
        if (LoadSettings($filename)){
            $rps->{file}{settings} = abs2rel($filename,$main::exeDir);
            if ($main::program eq "RCast3D"){LoadRod($rps->{file}{rod})}
            LoadLine($rps->{file}{line});
            LoadLeader($rps->{file}{leader});
            LoadDriver($rps->{file}{driver});
            main::UpdateFieldStates();
            
        }else{
            $rps->{file}{settings} = '';
            warn "Error:  Could not load settings from $filename.  Retaining previous settings file\n";
        }
    }
}

sub OnSettingsNone {
    $rps->{file}{settings} = '';
}


sub OnRodSelect {

	my ($dirs,$filename) = StrictRel2Abs($rps->{file}{rod},$main::exeDir);

    my $FSref = $main::mw->FileSelect(-directory=>$dirs,-defaultextension=>'.txt');
    $FSref->geometry('700x500');
    $filename = $FSref->Show;
    if ($filename){
		$rps->{file}{rod} = abs2rel($filename,$main::exeDir);
        SetFields(\@main::rodFields,"-state","disabled");
    }
}

sub OnRodNone {
    $rps->{file}{rod} = '';
    SetFields(\@main::rodFields,"-state","normal");
}

sub OnLineSelect {

	my ($dirs,$filename) = StrictRel2Abs($rps->{file}{line},$main::exeDir);

    my $FSref = $main::mw->FileSelect(-directory=>$dirs,-defaultextension=>'.txt');
    $FSref->geometry('700x500');
    $filename = $FSref->Show;
    if ($filename){
		$rps->{file}{line} = abs2rel($filename,$main::exeDir);
        SetFields(\@main::lineFields,"-state","disabled");
    }
}

sub OnLineNone {
    $rps->{file}{line} = '';
    SetFields(\@main::lineFields,"-state","normal");
}

sub OnLeaderSelect {

	my ($dirs,$filename) = StrictRel2Abs($rps->{file}{leader},$main::exeDir);

    my $FSref = $main::mw->FileSelect(-directory=>$dirs,-defaultextension=>'.txt');
    $FSref->geometry('700x500');
    $filename = $FSref->Show;
    if ($filename){
		$rps->{file}{leader} = abs2rel($filename,$main::exeDir);
        SetFields(\@main::leaderFields,"-state","disabled");
    }
}

sub OnLeaderNone {
    $rps->{file}{leader} = '';
    SetFields(\@main::leaderFields,"-state","normal");
}

sub OnDriverSelect {

	my ($dirs,$filename) = StrictRel2Abs($rps->{file}{driver},$main::exeDir);

    my $FSref = $main::mw->FileSelect(-directory=>$dirs,-filter=>'(*.txt)|(*.svg)');
    $FSref->geometry('700x500');
    $filename = $FSref->Show;
    if ($filename){
		$rps->{file}{driver} = abs2rel($filename,$main::exeDir);
        SetFields(\@main::driverFields,"-state","disabled");
    }
}

sub OnDriverNone {
    $rps->{file}{driver} = '';
    SetFields(\@main::driverFields,"-state","normal");
}


sub OnSaveSettings{

	my ($dirs,$filename) = StrictRel2Abs($rps->{file}{settings},$main::exeDir);

    $filename = $main::mw->getSaveFile(   -defaultextension=>'',
                                    -initialfile=>"$filename",
                                    -initialdir=>"$dirs");

    if ($filename){

        # Tk prevents empty or "." as filename, but let's make sure we have an actual basename, then put our own suffix on it:
        my ($basename,$dirs,$suffix) = fileparse($filename,'.prefs');
        if (!$basename){$basename = 'untitled'}
        $filename = $dirs.$basename.'.prefs';

        # Insert the selected file as the settings file:
		$rps->{file}{settings} = abs2rel($filename,$main::exeDir);
		
        my $conf = Config::General->new($rps);
        $conf->save_file($filename);
    }
}


sub OnRunPauseCont{
    
    my $label = $main::runPauseCont_btn->cget(-text);
	
    switch ($label)  {
        case "RUN"          {
            print "\nRUNNING$vs";
            if (!DoSetup()){print "RUN ABORTED$vs"; return}
            next;
        }
        case "CONTINUE" {
			my $pre	 = ($verbose<=1)?"":"\n";
			my $post = ($verbose==2)?"   ":"\n";
            print($pre."CONTINUING$post");
            next;
        }
        case ["CONTINUE","RUN"]     {
            $main::runPauseCont_btn ->configure(-text=>"PAUSE");
            
            SetDescendants($main::files_fr,"-state","disabled");
            SetDescendants($main::params_fr,"-state","disabled");

            $runControl{callerRunState} = 1;
            DoRun();
			
        }
        case "PAUSE"        {
			my $pre		= ($verbose==2)?"   ":"";
            print($pre."PAUSED\n");
			
            SetFields(\@main::verboseFields,"-state","normal");

            $runControl{callerRunState} = -1;
            $main::runPauseCont_btn->configure(-text=>"CONTINUE");
        }
    }
}


sub OnStop{

    $runControl{callerRunState} = 0;
    $main::runPauseCont_btn ->configure(-text=>"RUN");
	my $pre	= ($verbose==2)?"   ":"";
    print($pre."STOPPED\n");

    SetDescendants($main::files_fr,"-state","normal");
    SetDescendants($main::params_fr,"-state","normal");
    
    main::UpdateFieldStates();
}



sub OnSaveOut{

	# Start navigating where the last save was located:
	my ($dirs,$filename) = StrictRel2Abs($rps->{file}{save},$main::exeDir);

    $filename = $main::mw->getSaveFile(   -defaultextension=>'',
                                    -initialfile=>"$filename",
                                    -initialdir=>"$dirs");

    if ($filename){

        # Tk prevents empty or "." as filename, but let's make sure we have an actual basename.  The saving functions will put on their own extensions:
		my $basename;
        ($basename,$dirs) = fileparse($filename,'');
        if (!$basename){$basename = 'untitled'}
        $filename = $dirs.$basename;

        # Insert the selected file as the save file:
		$rps->{file}{save} = abs2rel($filename,$main::exeDir);
		
        DoSave($filename);
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


sub SetDescendants {
    my ($self,$option,$state) = @_;
    my @children = $self->children;

    foreach $a (@children){
        my $as = $a->cget(-state);
        if ($as) {$a->configure("$option"=>"$state")}
        SetDescendants($a,$option,$state);
    }
}



# Required package return value:
1;

__END__

=head1 NAME

RCommonInterface - All the common handling code for the control panels.

=head1 SYNOPSIS

use RCommonInterface;

=head1 EXPORT

HashCopy StrictRel2Abs OnVerbose ChangeVerbose SetTie LoadSettings OnSettingsSelect OnSettingsNone OnLineSelect OnLineNone OnLeaderSelect OnLeaderNone OnDriverSelect OnDriverNone OnSaveSettings OnRunPauseCont OnStop OnSaveOut SetOneField SetFields SetDescendants

use RCommonInterface;

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


