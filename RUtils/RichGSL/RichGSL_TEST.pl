# Perl code testing Rich's XS glue to the GSL ode_solver.
use strict;
use warnings;

my ($exeName,$exeDir,$basename,$suffix);
use File::Basename;
use Cwd qw(getcwd);
my $rhexDir;

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
	$exeDir = getcwd;
	print "Working in $exeDir\n";
	
	chdir "../..";
	
	$rhexDir = getcwd;     
    print "rhexDir=$rhexDir\n";
		
	#chomp($OS = `echo $^O`);
	#print "System is $OS\n";

}

# Put the launch directory on the perl path. This needs to be here, outside and below the BEGIN block.
use lib ($exeDir);
use lib ($rhexDir);

$" = "\n  "; 	# Set the double-quoted string field separator to "\n  ".
print "Module search path:\n  @INC\n\n";
$" = " ";	# Restore the string separator to space.


use Carp;
use PDL;
use PDL::NiceSlice;
#use PDL::AutoLoader;    # MATLAB-like autoloader.

use RUtils::Print;
use RUtils::Plot;

my $a = sequence(3);
pq($a);

#use RichGSL qw (rc_ode_solver);
use RUtils::DiffEq;

# Setup the the second-order nonlinear Van der Pol oscillator equation.


my $mu = 10;

sub func {
	my ($t,@y) = @_;

	my @f = ($y[1],-$y[0] - $mu*$y[1]*($y[0]*$y[0]-1));

	return @f;
}

sub jac {
	my ($t,@y) = @_;

	my $dFdy =	[
					[0 ,					1						],
					[-2*$mu*$y[0]*$y[1]-1,	-$mu*($y[0]*$y[0] - 1)	]
				];

	my $dFdt = [0, 0];
	
	my @Ft = @$dFdt;
	my $lenFt = @Ft;
	print "PerlJac returning dFdt=$dFdt, Ft=@Ft, length=$lenFt\n";
	
	my @Fy = @$dFdy;
	my $lenFy = @Fy;
	print "dFdy=$dFdy, Fy=@Fy, length=$lenFy\n";
	
	
	my $firstRowRef = ${Fy}[0];
	my @firstRow	= @$firstRowRef;
	print "firstRowRef=$firstRowRef, firstRow=@firstRow\n";
	
	my $secondRowRef = ${Fy}[1];
	my @secondRow	= @$secondRowRef;
	print "secondRowRef=$secondRowRef, secondRow=@secondRow\n";
	
	return($dFdy,$dFdt);
}


# Apply my solver:

my $t0			= 0;
my $t1			= 100;		# they like 100
my $num_steps	= 200;		# they like 100
my $num_y		= 2;
my @y			= (1,0);
my $step_type	= "msbdf_j";
my $h_init		= 1e-6;
my $eps_abs		= 1e-6;
my $eps_rel		= 0;


#    	@a = &Mytest::statfs("/blech");
#    	ok( scalar(@a) == 1 && $a[0] == 2 );
#    	@a = &Mytest::statfs("/");
#    	is( scalar(@a), 7 );

printf("About to call.\n");
my %opts_GSL   = (type=>"msbdf_j",h_init=>0.00001);

my $resultsRef = ode_solver([\&func,\&jac],[$t0,$t1,$num_steps],\@y,\%opts_GSL);

#my $resultsRef = rc_ode_solver(\&func,\&jac,$t0,$t1,$num_steps,$num_y,\@y,$step_type,$h_init,$eps_abs,$eps_rel);

my $resultsMat = pdl($resultsRef);
pq($resultsMat);

my %opt = (persist=>1);

Plot($resultsMat(1,:),\%opt);
PlotMat($resultsMat,\%opt);
sleep(2);
#die;

=for
print "results=@results\n";

for (my $i=0; $i <= $num_steps; $i++) {
	print "row=$i: ";
	for (my $j=0; $j <= $num_y; $j++) {
		print "$results[$i][$j],";
	}
	print "\n";
}
=cut


# my @results = &RichGSL::rc_ode_solver(\&func,\&jac,$t0,$t1,$num_steps,$num_y,\@y,$step_type,$h_init,$h_max,$eps_abs,$eps_rel);
#print "Returned from call.\n";

#	ok( scalar(@results) != 0);



#// Example step and jac functions:

#// int
#// func (double t, const double y[], double f[],
#//       void *params)
#// {
#//   (void)(t); /* avoid unused parameter warning */
#//   double mu = *(double *)params;
#//   f[0] = y[1];
#//   f[1] = -y[0] - mu*y[1]*(y[0]*y[0] - 1);
#//   return GSL_SUCCESS;
#// }

#// int
#// jac (double t, const double y[], double *dfdy,
#//      double dfdt[], void *params)
#// {
#//   (void)(t); /* avoid unused parameter warning */
#//   double mu = *(double *)params;
#//   gsl_matrix_view dfdy_mat
#//     = gsl_matrix_view_array (dfdy, 2, 2);
#//   gsl_matrix * m = &dfdy_mat.matrix;
#//   gsl_matrix_set (m, 0, 0, 0.0);
#//   gsl_matrix_set (m, 0, 1, 1.0);
#//   gsl_matrix_set (m, 1, 0, -2.0*mu*y[0]*y[1] - 1.0);
#//   gsl_matrix_set (m, 1, 1, -mu*(y[0]*y[0] - 1.0));
#//   dfdt[0] = 0.0;
#//   dfdt[1] = 0.0;
#//   return GSL_SUCCESS;
#// }

