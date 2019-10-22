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

use Exporter 'import';
our @EXPORT = qw(HashCopy StrictRel2Abs OnVerbose OnDebugVerbose ChangeVerbose OnReportVerbose SetTie LoadSettings LoadSettingsComplete OnSettingsSelect OnSettingsNone OnRodSelect OnRodNone OnLineSelect OnLineNone OnLeaderSelect OnLeaderNone OnLeaderMenuSelect OnDriverSelect OnDriverNone OnSaveSettings OnRunPauseCont OnStop OnSaveOut SetOneField SetFields SetDescendants OnLineEtc OnVerboseParam OnGnuplotView OnGnuplotViewCont);

#use Carp;
#use Carp qw(cluck longmess shortmess);
use Carp qw(cluck);

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

#use PDL;
    # Import main PDL module (see PDL.pm for equivalents).  In particular, imports PDL::Math, which redefines many POSIX math functions.  To get the original, call POSIX::aFunction.
#use PDL::NiceSlice;


use TryCatch;

use Config::General;
use Switch;
use File::Basename;
use File::Spec::Functions qw ( rel2abs abs2rel splitpath );

use RUtils::Print;

use RCommon qw (DEBUG $verbose $restoreVerbose $debugVerbose $reportVerbose $rps %runControl $doSetup $doRun $doSave $loadRod $loadDriver @rodFieldsDisable  @driverFieldsDisable $vs);
use RCommonLoad qw (LoadLine LoadLeader @lineFieldsDisable @leaderFieldsDisable);
use RCommonHelp;


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


sub HashCopy {

	## No checking whether the structures match.  However, failure is graceful in that if a requested field is not present in the source, an empty field is placed in the target.  The user will see that in the control panel and can correct it there.  On subsequent saving, the saved file will have the new key-value pair.
    my ($r_src,$r_target) = @_;
    
    foreach my $l0 (keys %$r_target) {
        foreach my $l1 (keys %{$r_target->{$l0}}) {
            $r_target->{$l0}{$l1} = $r_src->{$l0}{$l1};
        }
    }
}


sub HashCopyContent {

	## No checking whether the structures match.  However, does test source fields for being defined and non-empty.  In that case, does not overwrite the destination field.
    my ($r_src,$r_target) = @_;
    
    foreach my $l0 (keys %$r_target) {
        foreach my $l1 (keys %{$r_target->{$l0}}) {
			my $val = $r_src->{$l0}{$l1};
			if (defined($val) and $val ne ''){
            	$r_target->{$l0}{$l1} = $r_src->{$l0}{$l1};
			}
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
	SetTie($verbose);		# This needs to be here !!!!
	
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

sub OnReportVerbose {

	my $name = $rps->{integration}{reportVerboseName};
	$reportVerbose = substr($name,13);
	#print "\$reportVerbose = $reportVerbose\n";
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
#pq($verbose);
	#warn "Who called me?\n";
	#cluck "Who called me?\n";
	
    if ($verbose eq ''){die "\nASTONISHED THAT I AM CALLED.\n\nStopped"}   # Noop.
 
    elsif ($verbose<=$tieMax){
        tie *STDOUT, ref $main::status_rot, $main::status_rot;
        tie *STDERR, ref $main::status_rot, $main::status_rot;
    }else{
no warnings;	# Otherwise you may see a warning: untie attempted while xx inner references still exist ...  The problem itself is harmless.
        untie *STDOUT;
        untie *STDERR;
use warnings;
    }
}

use Data::Dump;

sub LoadSettings {
    my ($filename) = @_;
	
	## This is very permissive in that if config can find a hash in the file, and if the hash contains at least a correct rCast or rSwing identifier field, then any fields in the file that have the same keys as those in $rps will be copied. All other $rps fields will be unchanged.  Only if there is no attempt to copy will this be a noop.
    my $ok = 0;
	
	if ($filename) {
		if (-e $filename) {
			my $conf = Config::General->new($filename);
			my %src = $conf->getall();
			if (%src){
				my $tStr = ($main::program eq "RCast3D") ? "rCast" : "rSwing";
				if (exists($src{file}{$tStr})) {

					# Generally, I overwrite only dest fields whose corresponding src field is defined and non-empty.  In particular, this allows the built-in defaults to show through, which makes user set up easier.  However, in the special case of the file fields, it makes more sense to show empty if the source was:
					
					HashCopyContent(\%src,$rps);
					#HashCopy(\%src,$rps);
						# Need to copy so we don't break entry textvariable references.
					
					$rps->{file}{rCast}		= $src{file}{rCast};
					$rps->{file}{settings}	= $src{file}{settings};
					$rps->{file}{rod}		= $src{file}{rod};
					$rps->{file}{line}		= $src{file}{line};
					$rps->{file}{leader}	= $src{file}{leader};
					$rps->{file}{driver}	= $src{file}{driver};
					$rps->{file}{save}		= $src{file}{save};
					
					$ok = 1;
				} else {
					warn "\nWARNING: File $filename is corrupted or is not an $tStr settings file.\n";
				}
			} else {
				warn "\nWARNING: File $filename does not appear to be formatted as a settings file.\n";
			}
		}
	}
    return $ok;
}


sub LoadSettingsComplete {
    my ($filename) = @_;

	## A quite permissive attempt at loading, partially because LoadSettings() itself is permissive, but also since the subload calls are permissive on update, which is the case here.  This way the user gets to see the subload file names in there respective fields.  This should only happen if the files cannot be found.  If the file contents are not valid, that will cause an error on the attempt to run, which is just what happens for ordinary fields.

     if ($filename){
		if (!LoadSettings($filename)){
            warn "WARNING:  Could not load settings from $filename.  Retaining previous settings if any.\n";
			return 0;
		}
	}

	# If we get to here, we have either loaded settings or function was called with empty filename, which means we are using the built-in defaults ...
	
	# At this point we accept the new settings, even if the loads below don't work.  The user will see a complaint if the individual load files cannot be found, and $ok will be returned as 2:
	my $ok = 1;

	$rps->{file}{settings} = abs2rel($filename,$main::exeDir);

	if ($main::program eq "RCast3D"){
		if (!&$loadRod($rps->{file}{rod},1,1)){
			$ok=2;$rps->{file}{rod}='';&$loadRod('',1,1);
		}
	}
	if (!LoadLine($rps->{file}{line},1,1)){
		$ok=2;$rps->{file}{line}='';LoadLine('',1,1);
	}
	if (!LoadLeader($rps->{file}{leader},1,1)){
		$ok=2;$rps->{file}{leader}='';LoadLeader('',1,1);
	}
	if (!&$loadDriver($rps->{file}{driver},1,1)){
		$ok=2;$rps->{file}{driver}='';&$loadDriver('',1,1)
	}
	
	if ($ok){
		# All the disable arrays have been set by the load calls, so ok to align:
		main::AlignFieldStates();
		
		# Deal with output as indicated by the newly loaded settings:
		if (DEBUG){OnDebugVerbose()};
		OnReportVerbose();
		OnVerbose();
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
	
	LoadSettingsComplete($filename);
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

		my $tryFile = abs2rel($filename,$main::exeDir);
		if(&$loadRod($tryFile,1)){
			# Sets @rodFieldsDisable.
			print "OnRodSelect: \@rodFieldsDisable = @rodFieldsDisable\n";
			SetFields(\@main::rodFields,"-state","normal");
			SetFields(\@rodFieldsDisable,"-state","disabled");
			$rps->{file}{rod} = $tryFile;
		}
    }
}

sub OnRodNone {
    $rps->{file}{rod} = '';
	&$loadRod($rps->{file}{rod},1);
	print "OnRodNone: \@rodFieldsDisable = @rodFieldsDisable\n";
    SetFields(\@main::rodFields,,"-state","normal");
}

sub OnLineSelect {
	
	my ($dirs,$filename) = StrictRel2Abs($rps->{file}{line},$main::exeDir);

    my $FSref = $main::mw->FileSelect(-directory=>$dirs,-defaultextension=>'.txt');
    $FSref->geometry('700x500');
    $filename = $FSref->Show;
    if ($filename){
		my $tryFile = abs2rel($filename,$main::exeDir);
		if(LoadLine($tryFile,1)){
			# Sets @lineFieldsDisable.
			print "OnLineSelect: \@lineFieldsDisable = @lineFieldsDisable\n";
			SetFields(\@main::lineFields,"-state","normal");
			SetFields(\@lineFieldsDisable,"-state","disabled");
			$rps->{file}{line} = $tryFile;
		}
    }
}

sub OnLineNone {
    $rps->{file}{line} = '';
	LoadLine($rps->{file}{line},1);
	print "OnLineNone: \@lineFieldsDisable = @lineFieldsDisable\n";
    SetFields(\@main::lineFields,,"-state","normal");
}

sub OnLeaderSelect {

	my ($dirs,$filename) = StrictRel2Abs($rps->{file}{leader},$main::exeDir);

    my $FSref = $main::mw->FileSelect(-directory=>$dirs,-defaultextension=>'.txt');
    $FSref->geometry('700x500');
    $filename = $FSref->Show;
    if ($filename){
		my $tryFile = abs2rel($filename,$main::exeDir);
		if(LoadLeader($tryFile,1)){
			# Sets @leaderFieldsDisable.
			print "OnLeaderSelect: \@leaderFieldsDisable = @leaderFieldsDisable\n";
			SetFields(\@main::leaderFields,"-state","normal");
			SetFields(\@leaderFieldsDisable,"-state","disabled");
			$rps->{file}{leader} = $tryFile;
		}
    }
}

sub OnLeaderNone {
    $rps->{file}{leader} = '';
	LoadLeader($rps->{file}{leader},1);
	print "OnLeaderNone: \@leaderFieldsDisable = @leaderFieldsDisable\n";
    SetFields(\@main::leaderFields,"-state","normal");
	SetFields(\@leaderFieldsDisable,"-state","disabled");
}

sub OnLeaderMenuSelect {

	# It is not the menu's business to change the leader file field, so I don't simply call OnLeaderNone() here.  However, the desired effects on the other leader fields are the same.
	LoadLeader('',1);
	print "OnLeaderMenuSelect: \@leaderFieldsDisable = @leaderFieldsDisable\n";
    SetFields(\@main::leaderFields,"-state","normal");
	SetFields(\@leaderFieldsDisable,"-state","disabled");
}


sub OnDriverSelect {

	my ($dirs,$filename) = StrictRel2Abs($rps->{file}{driver},$main::exeDir);

    my $FSref = $main::mw->FileSelect(-directory=>$dirs,-filter=>'(*.txt)|(*.svg)');
    $FSref->geometry('700x500');
    $filename = $FSref->Show;
    if ($filename){
		my $tryFile = abs2rel($filename,$main::exeDir);
		if(&$loadDriver($tryFile,1)){
			# Sets @driverFieldsDisable.
			print "OnDriverSelect: \@driverFieldsDisable = @driverFieldsDisable\n";
			SetFields(\@main::driverFields,"-state","normal");
			SetFields(\@driverFieldsDisable,"-state","disabled");
			$rps->{file}{driver} = $tryFile;
		}
    }
}

sub OnDriverNone {
    $rps->{file}{driver} = '';
	&$loadDriver($rps->{file}{driver},1);
	print "OnDriverNone: \@driverFieldsDisable = @driverFieldsDisable\n";
    SetFields(\@main::driverFields,"-state","normal");
	SetFields(\@driverFieldsDisable,"-state","disabled");
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
            if (!&$doSetup()){print "RUN ABORTED$vs"; return}
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
            &$doRun();
			
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
    
    main::AlignFieldStates();
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
		
        &$doSave($filename);
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


