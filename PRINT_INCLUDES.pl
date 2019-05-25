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

use RPrint;
use PDL;
use PDL::NiceSlice;

die;

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
