//
//  rc_ode_solve
//  
//
//  Created by Rich Miller on 3/15/2019.
//
//

/*
	This is my wrapper for the GSL ode solver call, which is called by the perl code created by h2xs.
	
	Perl syntax:
	
	$result = c_ode_solver(\&eqn,\&jac,$num_steps,\@t,$num_y,\@y,$t1,
							$step_type,$h_init,$h_max,$epsabs,$epsrel,\@params);
	
	where the function args have the following form:
		@f = eqn($t,@y);
		(\@dFdy,\@dFdt) = jac($t,@y);
*/

#include <stdio.h>
#include <string.h>

#include "rc_ode_solve.h"

// From https://www.gnu.org/software/gsl/doc/html/ode-initval.html

#include <stdio.h>
#include <gsl/gsl_errno.h>
#include <gsl/gsl_matrix.h>
#include <gsl/gsl_odeiv2.h>

// Here are the headers copied from the constructed .xs:
#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

int ai = 7;
int bi = -3;
//int arr[] = {ai,bi};
int arr[] = {3,7};
void *test = &arr;


/* Available stepper types */

// Apparently there is not nice switch on strings in c, so

const gsl_odeiv2_step_type *
translate_step_type ( const char *step_type)
{
	//GSL_VAR const gsl_odeiv2_step_type *my_type;	// a non-pointer?
	const gsl_odeiv2_step_type *my_type;	// a non-pointer?
	
	if (strcmp(step_type,"msbdf")==0)			{my_type = gsl_odeiv2_step_msbdf;}
	else if (strcmp(step_type,"msadams")==0)	{my_type = gsl_odeiv2_step_msadams;}
	else if (strcmp(step_type,"bsimp")==0)		{my_type = gsl_odeiv2_step_bsimp;}
	else if (strcmp(step_type,"rk4imp")==0)		{my_type = gsl_odeiv2_step_rk4imp;}
	else if (strcmp(step_type,"rk2imp")==0)		{my_type = gsl_odeiv2_step_rk2imp;}
	else if (strcmp(step_type,"rk1imp")==0)		{my_type = gsl_odeiv2_step_rk1imp;}
	else if (strcmp(step_type,"rk8pd")==0)		{my_type = gsl_odeiv2_step_rk8pd;}
	else if (strcmp(step_type,"rkck")==0)		{my_type = gsl_odeiv2_step_rkck;}
	else if (strcmp(step_type,"rkf45")==0)		{my_type = gsl_odeiv2_step_rkf45;}
	else if (strcmp(step_type,"rk4")==0)		{my_type = gsl_odeiv2_step_rk4;}
	else if (strcmp(step_type,"rk2")==0)		{my_type = gsl_odeiv2_step_rk2;}
	else 										{my_type = 0;}

	return my_type;
}


// Callback to perl code from c is documented in https://perldoc.perl.org/perlcall.html.  See especially the section "Returning Data from Perl via the Parameter List".

// These functions are called by the stepper, and in turn call back to perl.  The total number of params is the first param, the addresses of the callback functions are the next two params, \&perlfunc and  \&perljac.  The next param is num_y.  Following PerlGSL::DiffEq, I do not implement that any remaining params are passed to perlfunc() and perljac().

//int bbi = test[1];
typedef struct {
  SV	*func;
  SV	*jac;
  int	num_y;
} Parameters;


static int
rc_func (double t, const double y[], double f[],
      void *params)
{
	// The called perl function has the syntax:
	//		@f = perlfunc($t,@y);
	
	int status		= GSL_SUCCESS;	// Optimism.
	
	
	// Dealing with void*, https://stackoverflow.com/questions/12448977/void-pointer-as-argument

	Parameters p	= *(Parameters*)params;
	int num_y		= p.num_y;
	SV *perlfunc		= p.func;

	
	dSP;
	int count;
	
	// Again following PerlGSL::DiffEq, the argument to the perl code is a perl scalar (t) and a perl array (@y), not a pointer to the array.  Thus, keeping perl's flattening behavior in that case, I need to just push all the array's SV's, one by one.  Recall that this only works if the array is the last argument!

	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	EXTEND(SP, 1+num_y);

	PUSHs(sv_2mortal(newSVnv(t)));
	for ( int i = 0; i<num_y; ++i ){
		PUSHs(sv_2mortal(newSVnv(y[i])));
	}

	PUTBACK;

	count = call_sv(perlfunc, G_ARRAY);
	
	SPAGAIN;

	if (count != num_y)
		croak ("RichGSL::rc_func: expected an array of %d doubles from perlfunc, got %d items.\n",num_y,count);
	
	//  What is actually returned in scalar context?  I presume a pointer to the actual return AV that continues to live somewhere because we still have an active pointer to it.
	
	// Again following the PerlGSL::DiffEq convention, these are all doubles, but if the perl code wants to indicate failure, it returns a string in the first array element.

	// If there were an easy SHIFTs I would use it, but couldn't find one.  So loading the array from the end to the beginning.
	for ( int i = num_y-1; i>=0; --i ){
		SV* elt = POPs;		// The elements of the returned array are SV's holding doubles, but because I want to test for a string value, I pop to an SV*.
		if (SvPOKp(elt)){				// Look for an SV holding a string.
			status = GSL_EBADFUNC;		// An int or something like it.
			f[i] = (double)status;		// Probably useless, since the solver will quit on seeing the bad return from this function.
		} else {
			f[i] = SvNV(elt);			// Get the double itself.
		}
	}
	
	FREETMPS;
	LEAVE;

  return status;
}


static int
rc_jac (double t, const double y[], double *dfdy,
     double dfdt[], void *params)
{
	// The called perl function has the syntax:
	//		(\@dFdy,\@dFdt) = perljac($t,@y);
	
	int status		= GSL_SUCCESS;	// Optimism.
	
	Parameters p	= *(Parameters*)params;
	int num_y		= p.num_y;
	SV *perljac		= p.jac;

	
	dSP;
	int count;
	
	ENTER;
	SAVETMPS;
	PUSHMARK(SP);
	EXTEND(SP, 1+num_y);

	PUSHs(sv_2mortal(newSVnv(t)));
	for ( int i = 0; i<num_y; ++i ){
		PUSHs(sv_2mortal(newSVnv(y[i])));
	}

	PUTBACK;

	count = call_sv(perljac, G_ARRAY);
	
	SPAGAIN;

	if (count != 2)
		croak ("RichGSL::rc_func: expected 1 array pointer from perlfunc, got %d items.\n",
			   count);
	
	//  What is actually returned in scalar context?  I presume a pointer to the actual return AV that continues to live somewhere because we still have an active pointer to it.
	
	// Again following the PerlGSL::DiffEq convention, these are all doubles, but if the perl code wants to indicate failure, it returns a string in the first array element.
	
	// The pop in reverse order.  I don't do any checking for bad in this function.
	
	// See https://perldoc.perl.org/perlcall.html#Alternate-Stack-Manipulation for the use of ST to access the stack on return in random order.  Doesn't seem worth doing here.  I didn't find a SHIFT to unload the stack on return.

	// I don't know if there is a SHIFT for accessing the return value.
	AV	*avdfdt = (AV*)POPi;		// A pointer is an IV, but cast to suppress warning.
	for ( int i = 0; i<num_y; ++i ){
		SV* elt	= av_shift(avdfdt);	// An array holds SV's.
		dfdt[i]	= SvNV(elt);		// I will presume a good double, without checking.
	}
	
	AV *avdfdy = (AV*)POPi;		// A pointer is an IV.
	for ( int i = 0; i<num_y; ++i ){
		AV *perl_row	= (AV*)SvIV(av_shift(avdfdy));	// An array holds SV's, and these SV hold pointers to arrays.
//		AV *perl_row	= av_shift(avdfdy);	// An array holds SV's.
		for ( int j = 0; j<num_y; ++j ){
			SV* elt	= av_shift(perl_row);	// An array holds SV's.
			dfdy[i*num_y+j]	= SvNV(elt);		// I will presume a good double, without checking.
			// ??? Worry about the ordering of perl vs c 2-d arrays.
		}
	}
	
	FREETMPS;
	LEAVE;

  return status;
}




// The correct, explicit function pointers:
//	int (*func) (double, const double, double, void*)
//	int (*jac) (double, const double, double*, double*, void*)

// My guess about the c call:
int
rc_ode_solver(void* func, void* jac, int num_steps, double *t, int num_y, double *y, double t1, char *step_type, double h_init, double h_max, double eps_abs, double eps_rel)
{

/*
	t should be a pointer to an array of doubles y should be a pointer to an array of arrays of num_dep doubles.  They will be expanded into an array of such numbers, one for each time step (including zero, so one more than num_steps).
*/
	
	// Load params:
	Parameters p;
	p.func		= func;
	p.jac		= jac;
	p.num_y		= num_y;
	
	void *params	= &p;
	
	gsl_odeiv2_system sys = {rc_func, rc_jac, num_y, params};
	
	const gsl_odeiv2_step_type *gsl_step_type
						 = translate_step_type (step_type);
	if ( !gsl_step_type ){
		printf ("error, unknown step type (%s)\n", step_type);
		return 1;

	}
	gsl_odeiv2_driver * d =
    	gsl_odeiv2_driver_alloc_y_new (&sys, gsl_step_type,
                                  h_init, eps_abs, eps_rel);

	double t0	= t[0];
	double yt[num_y];
	
	// Hard to believe you can't just assign one array to another.
	for ( int i = 0; i<num_y; ++i ) yt[i] = y[i];
		// Sic, in this case, I want the elements of y[0].

	double t_step	= (t1-t0)/num_steps;

	int status = 0;
	int j;
	for (j = 1; j <= 100; j++)
	  {
		double tj = j*t_step + t0;
		status = gsl_odeiv2_driver_apply (d, &t0, tj, yt);

		if (status != GSL_SUCCESS)
		  {
			printf ("error, return value=%d\n", status);
			break;
		  }

		// push t and ystep
		t[j]	= tj;
		for ( int i = 0; i<num_y; ++i ) y[j*num_y+i] = yt[i];
	  }

	gsl_odeiv2_driver_free (d);

	return status;
}


// =================


// The following func and jac solve the second-order nonlinear Van der Pol oscillator equation.  I will use them in RichGSL.t.


// Example step and jac functions:

// int
// func (double t, const double y[], double f[],
//       void *params)
// {
//   (void)(t); /* avoid unused parameter warning */
//   double mu = *(double *)params;
//   f[0] = y[1];
//   f[1] = -y[0] - mu*y[1]*(y[0]*y[0] - 1);
//   return GSL_SUCCESS;
// }

// int
// jac (double t, const double y[], double *dfdy,
//      double dfdt[], void *params)
// {
//   (void)(t); /* avoid unused parameter warning */
//   double mu = *(double *)params;
//   gsl_matrix_view dfdy_mat
//     = gsl_matrix_view_array (dfdy, 2, 2);
//   gsl_matrix * m = &dfdy_mat.matrix;
//   gsl_matrix_set (m, 0, 0, 0.0);
//   gsl_matrix_set (m, 0, 1, 1.0);
//   gsl_matrix_set (m, 1, 0, -2.0*mu*y[0]*y[1] - 1.0);
//   gsl_matrix_set (m, 1, 1, -mu*(y[0]*y[0] - 1.0));
//   dfdt[0] = 0.0;
//   dfdt[1] = 0.0;
//   return GSL_SUCCESS;
// }



//int
//main (void)
//{
//  double mu = 10;
//  gsl_odeiv2_system sys = {func, jac, 2, &mu};
//
//  gsl_odeiv2_driver * d =
//    gsl_odeiv2_driver_alloc_y_new (&sys, gsl_odeiv2_step_rk8pd,
//                                  1e-6, 1e-6, 0.0);
//  int i;
//  double t = 0.0, t1 = 100.0;
//  double y[2] = { 1.0, 0.0 };
//
//  for (i = 1; i <= 100; i++)
//    {
//      double ti = i * t1 / 100.0;
//      int status = gsl_odeiv2_driver_apply (d, &t, ti, y);
//
//      if (status != GSL_SUCCESS)
//        {
//          printf ("error, return value=%d\n", status);
//          break;
//        }
//
//      printf ("%.5e %.5e %.5e\n", t, y[0], y[1]);
//    }
//
//  gsl_odeiv2_driver_free (d);
//  return 0;
//}

