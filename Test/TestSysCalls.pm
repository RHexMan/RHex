# TestSysCalls.pm

#############################################################################
## Name:			TestSysCAlls
## Purpose:
## Author:			Rich Miller
## Modified by:
## Created:			2017/10/27
## Modified:		2019/3/4
## RCS-ID:
## Copyright:		(c) 2017 and 2019 Rich Miller
## License:			This program is free software; you can redistribute it and/or
##					modify it under the same terms as Perl itself
#############################################################################


package TestSysCalls;


use warnings;
use strict;
use POSIX ();
#require POSIX;
    # Require rather than use avoids the redefine warning when loading PDL.  But then I must always explicitly name the POSIX functions. See http://search.cpan.org/~nwclark/perl-5.8.5/ext/POSIX/POSIX.pod.  Implements a huge number of unixy (open ...) and mathy (floor ...) things.

use Carp;

use Exporter 'import';
our @EXPORT_OK = qw(TEST_RUN_PROCESS TEST_FORK_SYSTEM);

our $VERSION='0.01';


#use Chart::Gnuplot;
use Data::Dump;

use RUtils::Print;
#use threads;	# Would be needed if windows and Tk, but I sleep instead.

use Scalar::Util qw(looks_like_number);
#BEGIN { if ($^O =~ /MSWin32/) {require Scalar::Util; Scalar::Util->import( "looks_like_number" ); } }
#BEGIN { require Scalar::Util; Scalar::Util->import( "looks_like_number" ); }
#BEGIN { require Scalar::Util if $^O =~ /darwin/ }
BEGIN { require Win32 if $^O =~ /MSWin/ }
BEGIN { require Win32::Process if $^O =~ /MSWin/ }

#use if defined &DynaLoader::boot_DynaLoader,
#	"Unicode::Normalize" => qw(getCombinClass NFD); # Example from perldoc if.
#use if $^O =~ /darwin/,
#	"Unicode::Normalize" => qw(getCombinClass NFD);
#use if $^O =~ /darwin/,
#	"Scalar::Util" => qw(looks_like_number);	# These two lines work on the Mac.
#use if $^O =~ /MSWin32/,
#	"Scalar::Util" => qw(looks_like_number);	# These two produce an error on Mac.
#use if $^O =~ /MSWin32/,
#	"Unicode::Normalize" => qw(getCombinClass NFD);

#use if CONDITION, "MODULE", ARGUMENTS;

# Used in TEST_FORK_SYSTEM.  See this function below for extensive discussion.
my $gPdl = zeros(4);
#use Data::Structure::Util qw(unbless get_blessed get_refs);


sub TermType {

	my $OS;
	chomp($OS = `echo $^O`);
	#print "System is ($OS)\n";
	
	my $termType;
	if ($OS eq "MSWin32"){$termType = "windows"}
	elsif($OS eq "darwin"){$termType = "x11"}
	else {die "Unsupported system ($OS)\n"}
	
	return $termType;
}


## Testing to work out how to deal with the perl fork() call not working correctly in the presence of Tk on windows.  In the next routine we spawn an entirely separate process and have it operate.

sub ErrorReport {

	print Win32::FormatMessage( Win32::GetLastError());
}

sub TEST_RUN_PROCESS {

	my @args;
	#@args = ('C:\msys64\usr\bin\echo.exe',1,2,3,4,5); # Works with exec below.
	#@args = ('C:\Strawberry\c\bin\gnuplot.exe', 'gpInWin.txt'); # Works.
	#print "args = @args\n";
	print " In TEST_RUN_PROCESS, before call\n";
	
	my $processObj;
	Win32::Process::Create(	$processObj,
							#"C:\\msys64\\usr\\bin\\echo.exe",
							#"TEST_RUN_PROCESS test string",
							"C:\\Strawberry\\c\\bin\\gnuplot.exe",
							"gnuplot gpInWin.txt",	# Works!						
							0,
							NORMAL_PRIORITY_CLASS,
#							DETACHED_PROCESS,
							".") || die ErrorReport();
							
	my $processID = $processObj->GetProcessID();
	print "TEST_RUN_PROCESS, after call, processID=$processID\n";
}


## I used the following code to track down a plotting bug that occurred only in windows.  Sometimes after plotting, the RHex programs would freeze.  It turned that the problem was that in windows perl merely emulates a unix fork call, creating a new thread in the main process, not forking off an independent child process.  But Tk is not thread safe, and in particular, on the attempt to exit from the fork child, Tk tries to clean itself up and crashes both the child and main thread.  This happens even if the fork is invoked after Tk is set up, but before MainLoop() is called.

# As can be seen from the (commented) code below, I was never able to figure out how to make any child exit work.  If run in the absence of Tk, everything works just fine.

# My solution is a terrible KLUGE.  I simply invoke unending sleep on (any) return from the system call to gnuplot.  This is not practically very bad since as long as the plot window is not closed, it would have kept the child alive anyway, and on system return, the sleep doesn't use any CPU time.

# In fact, even this does not work reliably.  However, see TEST_RUN_PROCESS() above which is much more conservative (and actually leaves much smaller plot processes hanging around).


#use TryCatch;

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
			# So we know that fork() already detaches the child. 

		#print " In child, before early detach\n";
		#threads->detach();
			# With this here, get "Thread already detached ..." msg, and nothing more from child. Parent is still alive and well. I did read that a second attempt to detatch was an error.
		#print " In child, after early detach\n";
		
		## Checking whether PDL was causing the problem.  With no pdl, just the call to gnuplot, and threads->exit, this works entirely correctly. It also works correctly with use PDL and both local and global pdls defined in the parent. It's even ok with prints of the parent and global pdl's, except that as expected, the parent's values are not shown, rather something of the form SCALAR(0x...); Finally, even if a pdl is defined and printed in the child, everything works right.

=begin comment
		
		# Uncomment in the presence of Tk.
			## Try to get rid of any Tk that was copied:
			print "In child, Tk main window mw = $mw\n";
			my $ref = ref($mw);
			print "ref = $ref\n";		
			my $objects_arrayref = get_blessed($mw);
			print "In child, before unbless, objects_arrayref = $objects_arrayref\n";

			#print Data::Dump::dump($mw); print "\n";

			#try {$mw->destroy()}  # Causes immediate error.	TryCatch doesn't help.	
			#catch { print "In child catch, error = $@\n"}
		
			#$mw->destroy();  # Causes immediate error.
			#undef $mw;	# ref becomes empty, but no immediate crash.
		
			unbless($mw);
			$objects_arrayref = get_blessed($mw);
			$ref = ref($mw);
			print "ref = $ref\n";
			print "In child, after unbless, objects_arrayref = $objects_arrayref\n";
		
			#print Data::Dump::dump($mw); print "\n";
		
			undef %$mw;
				# No immediate crash, but error on exit.  So somebody (not mw) is keeping track of mw stuff.

			print "In child, after undef\n";
			#print Data::Dump::dump($mw); print "\n";
		
			#$mw = undef;	# Wrong conceptually.
			#$mw = 0;	# Wrong conceptually.
			#$mw->destroy();
				# This call results in the following error which kills the parent process and the child:
				#Free to wrong pool 5216530 not 632720 at C:\RHex\RHexReplot3D.pl line 950.
				#errorlevel = -1073741819			

=end comment

=cut

		print "In child, gPdl = $gPdl\n";		
		$gPdl = ones(7);
		print "In child, after reset, gPdl = $gPdl\n";
		print "In child, beforePdl = $beforePdl\n";
		
		my $cPdl = -sequence(3);
		print "In child, cPdl = $cPdl\n";

		my $thr = threads->self();
		print "Child thread pointer = $thr\n";
		#my $tid = threads->tid();
		#my $tid = $thr->tid();

		#threads->yield();
		
		## HERE IS THE SYSTEM CALL on my windows installation:
		my @args;
		#@args = ('C:\msys64\usr\bin\echo.exe',1,2,3,4,5); # Works with exec below.
		@args = ('C:\Strawberry\c\bin\gnuplot.exe', 'gpInWin.txt'); # Works.
		print "args = @args\n";
		#sleep(5);
		print " In child, before system call\n";
		#exec { $args[0] } @args;	# Exec doesn't help with the Tk problem.
		system { $args[0] } @args;
			# The difference between perl exec and system is that exec never returns, but system does. https://perldoc.perl.org/functions/exec.html
				
		print "In child (id=$$), returning from system call.\n";

		#my @cList = threads->list();
		#print "cList = @cList\n";
		
		sleep(1e6); # Without argument, forever. But that provokes a complaint, so for a very long time.
			# Sleeps forever.  However, may be interrupted if the process receives a signal such as SIGALRM .
		#sleep(1000);
		threads->exit();
			# The correct way to exit from any but the main thread.
		#exit 0;
		#CORE::exit();
			# Last two calls fail when the child returns, with message panic: restartop

		## Remember that if you don't terminate here, the code below the closing brace runs.  Under ordinary circumstances, this seems to work just fine.
	}
	#sleep(2);
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

return 1;


__END__

=head1 NAME

RUtils::Plot - Quick PDL 2D and 3D plotting functions wrapping Gnuplot system calls.  If no system gnuplot is available, $optsRef->{gnuplot} may be set to point to a local copy.

=head1 SYNOPSIS

use RUtils::Plot;
  
Plot($x0,$y0,label0[,...,$xn,$yn,$labeln,$title,$optsRef]);

   Initial args must be in  groups of three, matching pdl vector pairs followed by a label string.  After the last group, one or two string args may be passed.  If the last is a hash reference, it will be taken to be plot options as understood by gnuplot, and the next last, if there is one, will be taken to be the plot title.  If there are no options, and the last arg is a string, it will be used as the plot title.
 
  
PlotMat($inMat[,$vOffset][,$plotTitle][,$rPassedOpts]);

   A quick test plotting function.  Plots the later columns of the matrix against the first column with the desired vertical offset between traces.
 
Plot3D($x0,$y0,$z0,label0[,...,$xn,$yn,$zn,$labeln,$title,$optsRef]);

   A quick test plotting function.  Initial args must be in  groups of four, matching pdl vector pairs followed by a label string.  After the last group, one or two string args may be passed.  If the last is a hash reference, it will be taken to be plot options as understood by gnuplot, and the next last, if there is one, will be taken to be the plot title.  If there are no options, and the last arg is a string, it will be used as the plot title.
   
   
=head1 WARNING

If the calling program does not stay alive long enough, these plots sometimes don't happen.  If you put sleep(2) after the call, that usually fixes things.  I don't understand this, since the plot is supposed to fork off, and thereafter be independent.
 
=head1 EXPORT

plot, plotMat, and plot3D.


=head1 GNUPLOT REFERENCE (FOR CONVENIENCE)

From Chart/Gnuplot/Util.pm
 
 sub _lineType
 {
	my ($type) = @_;
	return($type) if ($type =~ /^\d+$/);
 
	# Indexed line type of postscript terminal of gnuplot
	my %type = (
 solid          => 1,
 longdash       => 2,
 dash           => 3,
 dot            => 4,
 'dot-longdash' => 5,
 'dot-dash'     => 6,
 '2dash'        => 7,
 '2dot-dash'    => 8,
 '4dash'        => 9,
	);
	return($type{$type});
 }
 
 
 # Convert named line type to indexed line type of gnuplot
 # This may subjected to change when postscript/gnuplot changes its convention
 sub _pointType
 {
	my ($type) = @_;
	return($type) if ($type =~ /^\d+$/);
 
	# Indexed line type of postscript terminal of gnuplot
	my %type = (
 dot               => 0,
 plus              => 1,
 cross             => 2,
 star              => 3,
 'dot-square'      => 4,
 'dot-circle'      => 6,
 'dot-triangle'    => 8,
 'dot-diamond'     => 12,
 'dot-pentagon'    => 14,
 'fill-square'     => 5,
 'fill-circle'     => 7,
 'fill-triangle'   => 9,
 'fill-diamond'    => 13,
 'fill-pentagon'   => 15,
 square            => 64,
 circle            => 65,
 triangle          => 66,
 diamond           => 68,
 pentagon          => 69,
 'opaque-square'   => 70,
 'opaque-circle'   => 71,
 'opaque-triangle' => 72,
 'opaque-diamond'  => 74,
 'opaque-pentagon' => 75,
	);
	return($type{$type});
 }
 
 
 L<https://metacpan.org/pod/Chart::Gnuplot#xtics,-ytics,-ztics>
 
 Chart Options Not Mentioned Above
 
 If Chart::Gnuplot encounters options not mentions above, it would convert them to Gnuplot set statements. E.g. if the chart object is
 
 $chart = Chart::Gnuplot->new(
 ...
 foo => "FOO",
 );
 
 the generated Gnuplot statements would be:
 
 ...
 set foo FOO
 
 This mechanism lets Chart::Gnuplot support many features not mentioned above (such as "cbrange", "samples", "view" and so on).
 
 
 All the details are in the gnuplot 5.2 manual.  The discussion of view (and equal axes) starts on p. 181.
 
 Syntax:
 set view <rot_x>{,{<rot_z>}{,{<scale>}{,<scale_z>}}}
 set view map {scale <scale>}
 set view {no}equal {xy|xyz}
 set view azimuth <angle>
 show view
 
 set view equal xyz
 
 
 The set xyplane command adjusts the position at which the xy plane is drawn in a 3D plot. The synonym "set ticslevel" is accepted for backwards compatibility.
 Syntax:
 
 gnuplot 5.2 191
 set xyplane at <zvalue>
 set xyplane relative <frac>
 set ticslevel <frac>        # equivalent to set xyplane relative
 show xyplane
 The form set xyplane relative <frac> places the xy plane below the range in Z, where the distance from the xy plane to Zmin is given as a fraction of the total range in z. The default value is 0.5. Negative values are permitted, but tic labels on the three axes may overlap.
 The alternative form set xyplane at <zvalue> fixes the placement of the xy plane at a specific Z value regardless of the current z range. Thus to force the x, y, and z axes to meet at a common origin one would specify set xyplane at 0.
 See also set view (p. 181), and set zeroaxis (p. 193).
 

=head1 AUTHOR

Rich Miller, E<lt>rich@ski.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2019 by Rich Miller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.28.1 or,
at your option, any later version of Perl 5 you may have available.


=cut





