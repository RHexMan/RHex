use warnings;
use strict;
use POSIX;

print "\n";
print "Running LIST_INCLUDES.pl ...";
print "\n\n";

print "\n";
print "Arch?=$^0\n";

use Config;
print "compiler=$Config{cc}\n";

#push @INC, '/Users/richmiller/perl5/lib/perl5/darwin-thread-multi-2level';
# can't simply push to change real copy!

# Print the perl path:

$" = "\n  "; 	# Set the double-quoted string field separator to "\n  ".
print "Module search path:\n  @INC\n\n";
$" = " ";	# Restore the string separator to space.

## NOTE that to add the current directory to the search path, you must include the following line (uncommented) in your .bash_profile file:
# export PERL_USE_UNSAFE_INC=1

# To find modules known to perlbrew, in terminal type <perlbrew list-modules>

# Find module groups that were installed (explicitly?) by cpan (not cpanm?).  ExtUtils is in the system:
#=for comment===========================================
 use ExtUtils::Installed;
 my $inst    = ExtUtils::Installed->new();
 my @modules = $inst->modules();
 $" = "\n  "; 	# Set the double-quoted string field separator to "\n  ".
 print "my utils:\n  @modules\n\n";
 $" = " ";	# Restore the string separator to space.
#=cut

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
