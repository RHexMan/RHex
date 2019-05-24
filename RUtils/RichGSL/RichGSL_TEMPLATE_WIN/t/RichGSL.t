# Before 'make install' is performed this script should be runnable with
# 'make test'. After 'make install' it should work as 'perl RichGSL.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;

use Test::More tests => 2;
BEGIN { use_ok('RichGSL') };

print "I got into RichGSL.t\n";

#########################


# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.


# Perl syntax:
#
#	$result = c_ode_solver(\&func,\&jac,$num_steps,\@t,$num_y,\@y,$t1,
#							$step_type,$h_init,$epsabs,$epsrel,\@params);
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
#print "rowRefs=@rowRefs\n";
my $lastRowRef	= $rowRefs[$num_steps];
#print "lastRowRef=$lastRowRef\n";
my @lastRow = @$lastRowRef;
print "lastRow=@lastRow\n";

# The last row should be:
#	[         100   -1.7582964  0.083697676]

ok( abs($lastRow[1] - -1.7582964) < 0.01);
#ok( abs($lastRow[1] - 4) < 0.01);	# Look for test failure.


# You can also run RichGSL_TEST.pl for test with plotted and fully tablulated results.


