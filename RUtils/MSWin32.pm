#!/usr/bin/perl

#############################################################################
## Name:			RUtils::MSWin32
## Purpose:
## Author:			Rich Miller
## Modified by:
## Created:			2019/11/17
## Modified:		2019/11/17
## RCS-ID:
## Copyright:		(c) 2019 Rich Miller
## License:			This program is free software; you can redistribute it and/or
##					modify it under the same terms as Perl itself
#############################################################################

## System dependent homebrew.  The calls here should match those in RUtils::Darwin.

package RUtils::MSWin32;

use warnings;
use strict;
use Carp;

use Exporter 'import';
our @EXPORT = qw( RunProcess);

our $VERSION='0.01';

use Win32::Process;
use Win32;

sub RunProcess {
	my ($cmd,$path) = @_;
	
	print "\nIn RunProcess (MSWin32), before call, path=$path\n cmd=$cmd\n";
	my $processObj;
	Win32::Process::Create(	$processObj,
							$path,
							$cmd,
							0,
							NORMAL_PRIORITY_CLASS,
#							DETACHED_PROCESS,
							".")
			||	die Win32::FormatMessage( Win32::GetLastError());

	my $processID = $processObj->GetProcessID();
	print "After call, processID=$processID\n";
			# The system call should be doing its own thing now.
}

# Required package return value:
1;

__END__

=head1 NAME

RUtils::MSWin32 - System dependent homebrew.

=head1 SYNOPSIS

  use RUtils::MSWin32;
 
  RunProcess($cmd,$path);
 
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


