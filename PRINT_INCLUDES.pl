#!/usr/bin/env perl

# This shebang causes the first perl on the path to be used, which will be the perlbrew choice if using perlbrew.


use warnings;
use strict;
use POSIX;


print `perl -v`;

my ($exeName,$exeDir,$basename,$suffix);
use File::Basename;
our $OS;

# https://perlmaven.com/argv-in-perl
# The name of the script is in [the perl variable] $0. The name of the program being
# executed, in the above case programming.pl, is always in the $0 variable of Perl.
# (Please note, $1, $2, etc. are unrelated!) 

BEGIN {	
	$exeName = $0;
	print "\nThis perl script was called as $exeName\n";
    
	($basename,$exeDir,$suffix) = fileparse($exeName,'.pl');

	chdir "$exeDir";  # See perldoc -f chdir
	print "Working in $exeDir\n";

	chomp($OS = `echo $^O`);
	print "System is $OS\n";
}

use lib ($exeDir);   # This needs to be here, outside and below the BEGIN block.
#push @INC, '/Users/richmiller/perl5/lib/perl5/darwin-thread-multi-2level';
# can't simply push to change real copy!

=begin comment

# PUT ANY QUICK TESTS HERE ===============

#use PDL;
#use PDL::NiceSlice;
#use RCommon qw(TEST_FORK_EXEC TEST_FORK_SYSTEM);
use threads;
use PDL;

my $gPdl = zeros(4);

sub TEST_FORK_SYSTEM {
	## Our fork parent does not wait for the child to exit.  Rather it calls something that will never return.  See https://metacpan.org/pod/threads

	my $beforePdl = sequence(5);
	
	my $pid = fork();	# The usual fork() is CORE::fork.  There is also available the Forks::Super module.
	if (!defined($pid)){
		die "Fork failed ($!)\n";		
	}elsif( $pid == 0 ){	# Code in these braces are what the child runs.
            # Zero is not really the child's PID, but just an indicator that this code is being run by the child.  To get the child's PID use my $childPid = $$;
			
		my $isDetached = threads->is_detached();
		print "In child, isDetached = $isDetached\n";

		#print " In child, before early detach\n";
		#threads->detach();
			# With this here, get "Thread already detached ..." msg, and nothing more from child. Parent is still alive and well.  Can I conclude that fork already detaches the child?  I did read that a second attempt to detatch was an error.
		#print " In child, after early detach\n";
		
		## With no pdl, just the call to gnuplot, and threads->exit, this works entirely correctly. It also works correctly with use PDL and both local and global pdls defined in the parent. It's even ok with prints of the parent and global pdl's, except that as expected, the parent's values are not shown, rather something of the form SCALAR(0x...); Finally, even if a pdl is defined and printed in the child, everything works right.
			
		print "In child, gPdl = $gPdl\n";
		print "In child, beforePdl = $beforePdl\n";
		
		my $cPdl = -sequence(3);
		print "In child, cPdl = $cPdl\n";

		my $thr = threads->self();
		print "Child thread pointer = $thr\n";
		my $tid = threads->tid();
		#my $tid = $thr->tid();

		#threads->yield();
		
		my @args;
		#@args = ('C:\msys64\usr\bin\echo.exe',1,2,3,4,5); # Works with exec below.
		@args = ('C:\Strawberry\c\bin\gnuplot.exe', 'gpInWin.txt'); # Works.
		print "args = @args\n";
		#sleep(5);
		print " In child, before system call\n";
		#exec { $args[0] } @args;
		system { $args[0] } @args;
		print "In child (id=$$), returning from system call.\n";

		my @cList = threads->list();
		#print "cList = @cList\n";
		threads->exit();
			# The correct way to exit from any but the main thread.
		#exit 0;
			# Fails when the child returns, with message panic: restartop
		## Remember that if you don't terminate here, the code below the closing brace runs.  Under ordinary circumstances, this seems to work just fine.
	}
	sleep(2);
	my $pthr = threads->self();
	print "Parent thread pointer = $pthr\n";
	my $ptid = $pthr->tid();
	print "In parent, ptid = $ptid\n";
	print "In parent (id=$$), child is (id=$pid)\n";
	my @pList = threads->list();
	#print "pList = @pList\n";

	my $afterPdl = ones(5);
	print "In parent, gPDL = $gPdl\n";
	print "In parent, beforePDL = $beforePdl\n";
	print "In parent, afterPDL = $afterPdl\n";
	
}



#TEST_FORK_EXEC();
TEST_FORK_SYSTEM();

sleep(8);
#exit 0;
#die;

= end comment

=cut


# ================

`echo dir`;

print "\n";
print "Arch?=$^0\n";

use Config;
print "compiler=$Config{cc}\n";
print "\n";

# Print the perl path:

$" = "\n  "; 	# Set the double-quoted string field separator to "\n  ".
print "Module search path:\n  @INC\n";
$" = " ";	# Restore the string separator to space.


## NOTE that to add the current directory to the search path, you must include the following line (uncommented) in your .bash_profile file:
# export PERL_USE_UNSAFE_INC=1

# To find modules known to perlbrew, in terminal type <perlbrew list-modules>

# Find module groups that were installed (explicitly?) by cpan (not cpanm?).  ExtUtils is in the system:
 use ExtUtils::Installed;
 my $inst    = ExtUtils::Installed->new();
 my @modules = $inst->modules();
# $" = "\n  "; 	# Set the double-quoted string field separator to "\n  ".
# print "my utils:\n  @modules\n\n";
# $" = " ";	# Restore the string separator to space.

# From https://stackoverflow.com/questions/135755/how-can-i-find-the-version-of-an-installed-perl-module
#perl -le 'eval "require $ARGV[0]" and print $ARGV[0]->VERSION' "$1"

# Modern modules all have a VERSION field:
my $version;
foreach my $module (@modules) {
	eval "require $module";
	$version = $module->VERSION;
	if (!defined($version)){$version = ''}
	print "$module $version\n";
}

die;

# Find the actual subroutines (with locations) that are available:
#=for comment===================================================
 use File::Find;
 print "Modules (with locations) actually available to this perlbrew perl:\n";
 my @files;
 find(
 {
 wanted => sub {
 push @files, $File::Find::fullname
 if $File::Find::fullname && -f $File::Find::fullname && /\.pm$/
 # Dangling symbolic links return undef.
 #        if -f $File::Find::fullname && /\.pm$/
 },
 follow => 1,
 follow_skip => 2,
 },
 @INC
 );
 print join "\n", @files;
#=cut
