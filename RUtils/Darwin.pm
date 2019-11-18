#!/usr/bin/perl

#############################################################################
## Name:			RUtils::Darwin
## Purpose:
## Author:			Rich Miller
## Modified by:
## Created:			2017/10/27
## Modified:		2017/10/27
## RCS-ID:
## Copyright:		(c) 2017 Rich Miller
## License:			This program is free software; you can redistribute it and/or
##					modify it under the same terms as Perl itself
#############################################################################

## System dependent homebrew.

package RUtils::Darwin;

use warnings;
use strict;
use Carp;

use Exporter 'import';
our @EXPORT = qw( RunProcess);

our $VERSION='0.01';

sub RunProcess {
	my ($cmd) = @_;

	#print "\nIn RunProcess (Darwin), before call, cmd=$cmd\n";
	
	my $pid = fork();	# The usual fork() is CORE::fork.  There is also available the Forks::Super module.
	if (!defined($pid)){
		croak "Fork failed ($!)\n";
	}elsif( $pid == 0 ){	# Code in these braces are what the child runs.
		# Zero is not really the child's PID, but just an indicator that this code is being run by the child.  To get the child's PID use my $childPid = $$;
	
		# This as in Chart::Gnuplot
		if (0){
			# We can exec(), since we are not expecting a return, and the should avoid another level of fork and exec that I read was done by system().
			exec("$cmd");
				# Which would never return, except if the exec itself fails, which we can check for.
		} else {
			# This is the way I was originally instructed to do it.
			my $err = `$cmd 2>&1`;
	#    			my $err;
	#    			system("$cmd");

			# Capture and process error message from Gnuplot
			if (defined $err && $err ne '')
			{
				my ($errTmp) = ($err =~ /\", line \d+:\s(.+)/);
				die "$errTmp\n" if (defined $errTmp);
				warn "$err\n";
			}
		}
		#print "After call, child processID=$$\n";
	}
}

# Required package return value:
1;

__END__

=head1 NAME

RUtils::Darwin - System dependent homebrew.

=head1 SYNOPSIS

  use RUtils::Darwin;
 
  RunProcess($cmd);
 
=head1 DESCRIPTION

=head1 EXPORT

RunProcess.

=head1 AUTHOR

Rich Miller, E<lt>rich@ski.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2019 by Rich Miller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.28.1 or,
at your option, any later version of Perl 5 you may have available.


=cut


