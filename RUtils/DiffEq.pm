package RUtils::DiffEq;

## A slightly modified by Rich Miller (2019) of PerlGSL::DiffEq by Joel Berger, Copyright (C) 2012 Joel Berger.  The modification calls rc_ode_solver from RichGSL, an XS module that static links to the Gnu Scientific Library's ODE solver.

use 5.008001;		# Require the same perl version as PerlGSL::DiffEq
use strict;
use warnings;
use Carp;

use Exporter 'import';
our @EXPORT = qw(ode_solver);

use RichGSL qw (rc_ode_solver);


my @step_types = qw(rk2 rk4 rkf45 rkck rk8pd rk1imp_j rk2imp_j rk4imp_j	bsimp_j msadams	msbdf_j);


sub ode_solver {
  my ($eqn, $t_range, $yRef, $opts) = @_;
  my $jac;
  if (ref $eqn eq 'ARRAY') {
    $jac = $eqn->[1] if defined $eqn->[1];
    $eqn = $eqn->[0];
  }
  croak "First argument must specify one or more code references" unless (ref $eqn eq 'CODE');

  ## Parse Options ##

  # Time range
  unless (ref $t_range eq 'ARRAY') {
    if (looks_like_number $t_range) {
      #if $t_range is a single number assume t starts at 0 and has 100 steps
      $t_range = [0, $t_range, 100];
    } else {
      croak "Could not understand 't range'";
    }
  }
	
  # Initial values of the dependent variables
  my $num_y = @{$yRef};
  my @saveY = @{$yRef};
  #print "num_y=$num_y\n";
  #print "saveY=@saveY\n";
	

	# Step type
	my $step_type = "";
	if ( exists $opts->{type}) {
		$step_type = $opts->{type};
		my @matches = grep { /$step_type/ } @step_types;
		if (!@matches) {$step_type = ""}
	}
	if (!$step_type){
		carp "Using default step type 'rk8pd'\n";
		$step_type = "rk8pd";
	}

  # h step configuration
  my $h_init;
#  my $h_max  = (exists $opts->{h_max} ) ? $opts->{h_max}  : 0;
  if (exists $opts->{h_init}) {
    $h_init = $opts->{h_init};

    # if the user specifies an h_init greater than h_max then croak
#    if ($h_max && ($h_init > $h_max)) {
#      croak "h_init cannot be set greater than h_max";
#    }
  } else {
    $h_init = 1e-6;

    # if the default h_init would be greater tha h_max then set h_init = h_max
#    if ($h_max && ($h_init > $h_max)) {
#      $h_init = $h_max;
#    }
  }

  # Error levels
  my $epsabs = (exists $opts->{epsabs}) ? $opts->{epsabs} : 1e-6;
  my $epsrel = (exists $opts->{epsrel}) ? $opts->{epsrel} : 0.0;

  # Error types (set error scaling with logical name)
#  my ($a_y, $a_dydt) = (1, 0);
#  if (exists $opts->{scaling}) {
#    if ($opts->{scaling} eq 'y') {
#      # This is currently the default, do nothing
#    } elsif ($opts->{scaling} eq 'yp') {
#      ($a_y, $a_dydt) = (1, 0);
#    } else {
#      carp "Could not understand scaling specification. Using defaults.";
#    }
#  }

  # Individual error scalings (overrides logical name if set above)
#  $a_y = $opts->{'a_y'} if (exists $opts->{'a_y'});
#  $a_dydt = $opts->{'a_dydt'} if (exists $opts->{'a_dydt'});

  ## Run Solver ##
  	my ($t0,$t1,$num_steps) = map {$t_range->[$_]} (0..2);

=for
	print("eqn=$eqn,jac=$jac\n");
	print("t0=$t0,t1=$t1,num_steps=$num_steps\n");
	my @y = @$yRef;
	print("y=@y\n");
	print("step_type=$step_type,h_init=$h_init,epsabs=$epsabs,epsrel=$epsrel\n");
=cut
	
	my $results = rc_ode_solver($eqn,$jac,$t0,$t1,$num_steps,$num_y,$yRef,$step_type,$h_init,$epsabs,$epsrel);
	
	# Test for empty results, and return a thing of the form of results containing the solution at the initial time:
	my $count = @{$results};
	if (!$count){
		my @row;
		push(@row,$t0);
		push(@row,@saveY);
		my $rowRef = \@row;
		my @rowRefs;
		push(@rowRefs,$rowRef);
		$results = \@rowRefs;
	}

  # Run the solver at the C/XS level
#  my $result;
#  {
#    local @_; #be sure the stack is clear before calling c_ode_solver!
#    $result = c_ode_solver(
#      $eqn, $jac, @$t_range, $step_type, $h_init, $h_max, $epsabs, $epsrel, $a_y, $a_dydt);
#  }

  return $results;
}


1;

__END__

=head1 NAME

RUtils::Diffeq - a wrapper for RichGSL::rc_ode_solve, which is a static build of a portion of the GSL library.  This interface is a slight modification of PerlGSL::DiffEq written by Joel Berger.  The only significant difference in the interface is that here the initial values of the dependent variables must be passed. See PerlGSL::DiffEq for a complete description.

=head1 SYNOPSIS

use RUtils::DiffEq;
$solution = ode_solver([\&func,\&jac],[$startT,$stopT,$numSteps],\@y,\%opts));
	
func and jac are functions, $startT,$stopT and $numSteps are perl scalars, @y is a perl array that holds the initial values of the dependent variables, and opts is a hash.  On return, $results is the standard pointer to a 2D perl array, that is, a pointer to an array of pointers, each a pointer to an array.  The innermost arrays have length 1 more than the length of the array @y.  The 0th entry holds a time and the rest of the entries hold the values of the dependent variables at that time.  Reported times are equally spaced so that if the calculation goes to completion, the total number of reported steps will be $numSteps+1, since the initial time and values as well as the final time and values are returned.  If, either because of a problem detected by the solver or because of a user interrupt, the calculation is cut short, only the valid, so far computed, steps are reported.  In particular, this means that at least the initial time and values are returned.
	
$opts[type] select the particular stepper to be used, and may be any one of the strings: msbdf_j, rk4imp_j, rk2imp_j, rk1imp_j, bsimp_j ,rkf45 ,rk4, rk2, rkck, rk8pd, or msadams.

The function args must have the form

=over

@f = func($t,@y);

=back

and

=over

(\@dFdy,\@dFdt) = jac($t,@y);

=back

where \@dFdy is the Jacobian matrix formed as an array reference containing array references. It should be square where each dimension is equal to the number of differential equations. Each "row" contains the derivatives of the related differential equations with respect to each dependant parameter, respectively.

=over

[

  [ d(dy[0]/dt)/d(y[0]), d(dy[0]/dt)/d(y[1]), ... ],
 
  [ d(dy[1]/dt)/d(y[0]), d(dy[1]/dt)/d(y[1]), ... ],
 
  ...
 
  [ ..., d(dy[n]/dt)/d(y[n])],
 
]

=back

and \@dFdt contains the derivatives of the differential equations with respect to the independant parameter.

=over

[ d(dy[0]/dt)/dt, ..., d(dy[n]/dt)/dt ]

=back

The Jacobian code reference is only needed for certain step types, those whose names end in C<_j>.


=head1 AUTHOR

Rich Miller, E<lt>rich@ski.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2019 by Rich Miller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

The GSL is licensed under the terms of the GNU General Public License (GPL)

=cut
