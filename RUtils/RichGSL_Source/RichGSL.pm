package RichGSL;

use 5.008001;		# Require the same perl version as PerlGSL::DiffEq
use strict;
use warnings;
use Carp;

require Exporter;
use AutoLoader;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use RichGSL ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	rc_ode_solver
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '0.01';

sub AUTOLOAD {
    # This AUTOLOAD is used to 'autoload' constants from the constant()
    # XS function.

    my $constname;
    our $AUTOLOAD;
    ($constname = $AUTOLOAD) =~ s/.*:://;
    croak "&RichGSL::constant not defined" if $constname eq 'constant';
    my ($error, $val) = constant($constname);
    if ($error) { croak $error; }
    {
	no strict 'refs';
	# Fixed between 5.005_53 and 5.005_61
#XXX	if ($] >= 5.00561) {
#XXX	    *$AUTOLOAD = sub () { $val };
#XXX	}
#XXX	else {
	    *$AUTOLOAD = sub { $val };
#XXX	}
    }
    goto &$AUTOLOAD;
}

require XSLoader;
XSLoader::load('RichGSL', $VERSION);

# Preloaded methods go here.



1;

__END__
__POD__
=head1 NAME

RichGSL - A perl XS that interfaces with a static build of the part of the GSL that implements ODE solution.  This was done before by Joel Berger, with the more common dynamic linking.  A higher-level perl interface is available in RUtils::RDiffEq, which is more completely documented.

=head1 SYNOPSIS

 use RichGSL qw (rc_ode_solver);
 
 and call
 	my $results = rc_ode_solver($eqn,$jac,$t0,$t1,$num_steps,$num_y,$y0Ref,$step_type,$h_init,$epsabs,$epsrel);
	
  The first argument is a pointer to the test function, and the second a pointer to a function that supplies the jacobian matrix that is required by some of the particular stepping routines, as indicated below.  The integration is run from t0 to t1 and results are reported at equal intervals whose length is determined by num_steps.  Num_y is the number of dependent variables, and y0Ref is a pointer to the initial values of the dependent variables.

  The C-code that calls the library is in the file rc_ode_solver.c in the XS project.  A full description of the GSL ODE library functions may be found at https://www.gnu.org/software/gsl/doc/html/ode-initval.html.

 

==head1 EXPORTED FUNCTIONS

=head2 rc_ode_solver

=head3 the differential equation system

The differential equation system is defined in a code reference (in the example C<$diffeq_code_ref>). This code reference (or anonymous subroutine) must have a specific construction:

=over 

=item *

The first argument will be time (or the independent parameter) and the rest will be the function values in the same order as the initial conditions. The returns in this case should be the values of the derivatives of the function values.

If one or more of the returned values are not numbers (as determined by L<Scalar::Util> C<looks_like_number>), the solver will immediately return all calculations up until (and not including) this step, accompanied by a warning. This may be done intentionally to exit the solve routine earlier than the end time specified in the second argument.

=item *

Please note that as with other differential equation solvers, any higher order differential equations must be converted into systems of first order differential equations. 

=back

Optionally the system may be further described with a code reference which defines the Jacobian of the system (in the example C<$jacobian_code_ref>). Again, this code reference has a specific construction. The arguments will be passed in exactly the same way as for the equations code reference (though it will not be called without arguments). The returns should be two array references. 

=over

=item *

The first is the Jacobian matrix formed as an array reference containing array references. It should be square where each dimension is equal to the number of differential equations. Each "row" contains the derivatives of the related differential equations with respect to each dependant parameter, respectively.

 [
  [ d(dy[0]/dt)/d(y[0]), d(dy[0]/dt)/d(y[1]), ... ],
  [ d(dy[1]/dt)/d(y[0]), d(dy[1]/dt)/d(y[1]), ... ],
  ...
  [ ..., d(dy[n]/dt)/d(y[n])],
 ]

=item *

The second returned array reference contains the derivatives of the differential equations with respect to the independant parameter.

 [ d(dy[0]/dt)/dt, ..., d(dy[n]/dt)/dt ]

=back

The Jacobian code reference is only needed for certain step types, those step types whose names end in C<_j>.

=head3 required arguments

C<ode_solver> requires two arguments, they are as follows:

=head4 first argument

The first argument may be either a code reference or an array reference containing one or two code references. In the single code reference form this represents the differential equation system, constructed as described above. In the array reference form, the first argument must be the differential equation system code reference, but now optionally a code reference for the Jacobian of the system may be supplied as the second item.

=head4 second argument

The second argument, C<$t_range>, specifies the time values that are used for the calculation. This may be used one of two ways:

=over

=item *

An array reference containing numbers specifying start time, finish time, and number of steps.

=item *

A scalar number specifying finish time. In this case the start time will be zero and 100 steps will be used.

=back

=head3 optional argument (the options hash reference)

The third argument, C<$opts_hashref>, is a hash reference containing other options. They are as follows:

=over

=item *

C<type> specifies the step type to be used. The default is C<rk8pd>. The available step types can be found using the exportable function L</get_step_types>. Those step types whose name ends in C<_j> require the Jacobian.

=item *

C<h_init> the initial "h" step used by the solver. Defaults to C<1e-6>.

=item *

C<h_max> the maximum "h" step allowed to the adaptive step size solver. Set to zero to use the default value specified the GSL, this is the default behavior if unspecified. Note: the module will croak if C<h_init> is set greater than C<h_max>, however if C<h_init> is not specified and the default would violate this relation, C<h_init> will be set to C<h_max> implicitly.

=item * Error scaling options. These all refer to the adaptive step size contoller which is well documented in the L<GSL manual|http://www.gnu.org/software/gsl/manual/html_node/Adaptive-Step_002dsize-Control.html>. 

=over

=item *

C<epsabs> and C<epsrel> the allowable error levels (absolute and relative respectively) used in the system. Defaults are C<1e-6> and C<0.0> respectively.

=item *

C<a_y> and C<a_dydt> set the scaling factors for the function value and the function derivative respectively. While these may be used directly, these can be set using the shorthand ...

=item *

C<scaling>, a shorthand for setting the above option. The available values may be C<y> meaning C<{a_y = 1, a_dydt = 0}> (which is the default), or C<yp> meaning C<{a_y = 0, a_dydt = 1}>. Note that setting the above scaling factors will override the corresponding field in this shorthand.

=back

=back

=head3 return

The return is an array reference of array references. Each inner array reference will contain the time and function value of each function in order as above. This format allows easy loading into L<PDL> if so desired:

 $pdl = pdl($solution);

of course one may recover one column by simple use of a C<map>:

 @solution_t_vals  = map { $_->[0] } @$solution;
 @solution_y1_vals = map { $_->[1] } @$solution;
 ...

For a usage example see the L</SYNOPSIS> for a sine function given by C<y''(t)=-y(t)>.

=head1 EXPORTABLE FUNCTIONS

=head2 get_step_types

Returns the available step types which may be specified in the L</ode_solver> function's options hashref. Note that those step types whose name end in C<_j> require the Jacobian.

=head2 get_gsl_version

A simple function taking no arguments and returning the version number of the GSL library as specified in C<gsl/gsl_version.h>. This was originally used for dependency checking but now remains simply for the interested user.

=head1 FUTURE GOALS

On systems with PDL installed, I would like to include some mechanism which will store the numerical data in a piddle directly, saving the overhead of creating an SV for each of the pieces of data generated. I envision this happening as transparently as possible when PDL is available. This will probably take some experimentation to get it right.

=head1 SEE ALSO

=over

=item L<PerlGSL>

=item L<Math::ODE>

=item L<Math::GSL::ODEIV>

=item L<GSL|http://www.gnu.org/software/gsl/>

=item L<PDL>, L<website|http://pdl.perl.org> 

=back

=head1 SOURCE REPOSITORY

L<http://github.com/jberger/PerlGSL-DiffEq>

=head1 AUTHOR

Rich Miller, E<lt>rich@ski.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2019 by Rich Miller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

The GSL is licensed under the terms of the GNU General Public License (GPL)

=cut
