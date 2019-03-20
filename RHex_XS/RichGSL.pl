# Before 'make install' is performed this script should be runnable with
# 'make test'. After 'make install' it should work as 'perl RichGSL.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;


use Carp;
print "I got into RichGSL.t.\n";

use RichGSL qw (rc_ode_solver);

#########################


# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.


# Perl syntax:
#
#	@result = c_ode_solver(\&func,\&jac,$num_steps,\@t,$num_y,\@y,$t1,
#							$step_type,$h_init,$h_max,$epsabs,$epsrel,\@params);
#
#	where the function args have the following form:
#		@f = func($t,@y);
#		(\@dFdy,\@dFdt) = jac($t,@y);
#


# Setup the the second-order nonlinear Van der Pol oscillator equation.

print "I got to the eqn setup.\n";

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
	
	return ($dFdt);		# Wants an array containing the point, so array context.
	#return($dFdy,$dFdt);
}


# Apply my solver:

my $t0			= 0;
my $t1			= 5;		# they like 100
my $num_steps	= 5;		# they like 100
my $num_y		= 2;
my @y			= (1,0);
my $step_type	= "msbdf";
my $h_init		= 1e-6;
my $h_max		= 1;
my $eps_abs		= 1e-6;
my $eps_rel		= 0;


#    	@a = &Mytest::statfs("/blech");
#    	ok( scalar(@a) == 1 && $a[0] == 2 );
#    	@a = &Mytest::statfs("/");
#    	is( scalar(@a), 7 );

printf("About to call.\n");

my @results = rc_ode_solver(\&func,\&jac,$t0,$t1,$num_steps,$num_y,\@y,$step_type,$h_init,$h_max,$eps_abs,$eps_rel);
croak "Croak\n\n";



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

