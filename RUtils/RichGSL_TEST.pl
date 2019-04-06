# Before 'make install' is performed this script should be runnable with
# 'make test'. After 'make install' it should work as 'perl RichGSL.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;


use Carp;
use RichGSL qw (rc_ode_solver);

use RUtils::Print;
use RUtils::Plot;

use PDL;
# Import main PDL module (see PDL.pm for equivalents).  In particular, imports PDL::Math, which redefines many POSIX math functions.  To get the original, call POSIX::aFunction.
use PDL::NiceSlice;



print "I got into RichGSL_TEST.pm\n";

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

    # Must return the following two array refs:
    
    # The first is the Jacobian matrix formed as an array reference containing array references. It should be square where each dimension is equal to the number of differential equations. Each "row" contains the derivatives of the related differential equations with respect to each dependant parameter, respectively.
    
    # [
    # [ d(dy[0]/dt)/d(y[0]), d(dy[0]/dt)/d(y[1]), ... ],
    # [ d(dy[1]/dt)/d(y[0]), d(dy[1]/dt)/d(y[1]), ... ],
    # ...
    # [ ..., d(dy[n]/dt)/d(y[n])],
    # ]
    
    # The second returned array reference contains the derivatives of the differential equations with respect to the independant parameter.
    
    # [ d(dy[0]/dt)/dt, ..., d(dy[n]/dt)/dt ]
    
    my $dFdy =  [           # Square bracket makes this an array reference.
                    [0,1],
                    [-1-$mu*$y[1]*2*$y[0],-$mu*($y[0]*$y[0] - 1)],
                ];
    
    my $dFdt = [0,0];
    
    return ($dFdy,$dFdt);
}


# Apply my solver:

my $t0			= 0;
my $t1			= 100;
my $num_steps	= 100;
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

my $results = &RichGSL::rc_ode_solver(\&func,\&jac,$t0,$t1,$num_steps,$num_y,\@y,$step_type,$h_init,$eps_abs,$eps_rel);

my @rowRefs = @$results;
print "rowRefs=@rowRefs\n";
my $lastRowRef	= $rowRefs[$num_steps];
print "lastRowRef=$lastRowRef\n";
my @lastRow = @$lastRowRef;
print "lastRow=@lastRow\n";

print "On return: results=$results\n";
my $pdlResults = pdl($results);
pq($pdlResults);
PlotMat($pdlResults);
sleep(2);


# my @results = &RichGSL::rc_ode_solver(\&func,\&jac,$t0,$t1,$num_steps,$num_y,\@y,$step_type,$h_init,$h_max,$eps_abs,$eps_rel);
#print "Returned from call.\n";




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

