//  rc_ode_solve
//
//  Created by Rich Miller on 3/15/2019.

/*
	This is my wrapper for the GSL ode solver call, which is called by the perl code created by h2xs.  See the GSL documentation at https://www.gnu.org/software/gsl/doc/html/ode-initval.html
	
	Perl syntax:
	
	use RichGSL qw (rc_ode_solver);
	
	$result = rc_ode_solver(\&func,\&jac,$t0,$t1,$num_steps,$num_y,\@y,$step_type,$h_init,$eps_abs,$eps_rel);
	
	where $results is a reference to an 2-d array whose rows hold the values of the dependent variables at each of the (uniformly spaced) set of reporting times.

	where the function args have the following form:
		@f				= func($t,@y);
		(\@dFdy,\@dFdt)	= jac($t,@y);
*/

// See the perldoc xs documents for all the details:  https://perldoc.perl.org/perlguts.html https://perldoc.perl.org/perlxstut.html  https://perldoc.perl.org/perlxs.html https://perldoc.perl.org/perlcall.html https://perldoc.perl.org/perlxstypemap.html The code below gives good examples of how things work in practice.

#include <stdio.h>
#include <string.h>

#include "rc_ode_solver.h"

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


static int check = 0;

/* Available stepper types */

const gsl_odeiv2_step_type *
translate_step_type ( const char *step_type)
{
	//GSL_VAR const gsl_odeiv2_step_type *my_type;	// a non-pointer?
	const gsl_odeiv2_step_type *my_type;	// a non-pointer?
	
	if (strcmp(step_type,"msbdf_j")==0)			{my_type = gsl_odeiv2_step_msbdf;}
	else if (strcmp(step_type,"msadams")==0)	{my_type = gsl_odeiv2_step_msadams;}
	else if (strcmp(step_type,"bsimp_j")==0)	{my_type = gsl_odeiv2_step_bsimp;}
	else if (strcmp(step_type,"rk4imp_j")==0)	{my_type = gsl_odeiv2_step_rk4imp;}
	else if (strcmp(step_type,"rk2imp_j")==0)	{my_type = gsl_odeiv2_step_rk2imp;}
	else if (strcmp(step_type,"rk1imp_j")==0)	{my_type = gsl_odeiv2_step_rk1imp;}
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
	
	if (check>1) printf("  Entering func\n");
	
	int status		= GSL_SUCCESS;	// Optimism.
	
	
	// Dealing with void*, https://stackoverflow.com/questions/12448977/void-pointer-as-argument

	Parameters p	= *(Parameters*)params;
	int num_y		= p.num_y;
	SV *perlfunc		= p.func;

	if (check>1){
		printf("t=%f, y=",t);
		for (int i = 0; i<num_y; i++){printf("%f,",y[i]);}
		printf("\n");
	}
	
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
		croak ("ERROR: RichGSL::rc_func - expected an array of %d doubles from perlfunc, got %d items.\n",num_y,count);
	
	//  What is actually returned in scalar context?  I presume a pointer to the actual return AV that continues to live somewhere because we still have an active pointer to it.
	
	// Again following the PerlGSL::DiffEq convention, these are all doubles, but if the perl code wants to indicate failure, it returns a string in the first array element.

	// If there were an easy SHIFTs I would use it, but couldn't find one.  So loading the array from the end to the beginning.
	for ( int i = num_y-1; i>=0; --i ){
		SV* elt = POPs;		// The elements of the returned array are SV's holding doubles, but because I want to test for a string value, I pop to an SV*.
		if (SvPOKp(elt)){				// Look for an SV holding a string.
			status = GSL_EBADFUNC;		// An int or something like it.
			f[i] = (double)status;		// Probably useless, since the solver will quit on seeing the bad return from this function.
		} else {
			if (check && !(SvNOKp(elt) || SvIOKp(elt))) croak("ERROR: RichGSL::rc_func - detected bad element type\n");
			f[i] = SvNV(elt);			// Get the double itself.
		}
		
	}
	
	if (check>1){
		printf("f=");
		for ( int i = num_y-1; i>=0; --i )printf("%f,",f[i]);
		printf("\n  Exiting func\n");
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


	if (check>1) printf("  Entering jac\n");
	
	int status		= GSL_SUCCESS;	// Optimism.
	
	Parameters p	= *(Parameters*)params;
	int num_y		= p.num_y;
	SV *perljac		= p.jac;

	if (check>1){
		printf("t=%f, y=",t);
		for (int i = 0; i<num_y; i++){printf("%f,",y[i]);}
		printf("\n");
	}
	
	
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
		croak ("ERROR:  RichGSL::rc_jac - expected 1 array pointer from perlfunc, got %d items.\n",
			   count);

	SV* tempRef;
	
	SV*	dfdtShell = POPs;

	tempRef = NULL;
	if (SvROK(dfdtShell)){
		tempRef = SvRV(dfdtShell);
		if (SvTYPE(tempRef) != SVt_PVAV) tempRef = NULL;
	}
	if (check && !tempRef) croak("ERROR: RichGSL::rc_jac - dfdt must be a reference to an array.\n");

	AV* dfdtRef = (AV*)tempRef;
	SSize_t top_index;
	
	if (check){
		top_index = av_top_index(dfdtRef);
		if (check>1) printf("top_index=%ld\n",top_index);
		if (top_index+1 != num_y) croak("ERROR: RichGSL::rc_jac - delivered (%ld) elements, not (%d) as required\n",top_index+1,num_y);
	}
	
	for ( int i = 0; i<num_y; ++i ){
		SV* elt	= av_shift(dfdtRef);	// An array holds SV's.
		if (check && !(SvNOKp(elt) || SvIOKp(elt))) croak("ERROR: RichGSL::rc_jac - detected non-double element\n");
		dfdt[i]	= SvNV(elt);
	}
	
	if (check>1){
		printf("dfdt=");
		for ( int i = 0; i<num_y; ++i ) printf("%f,",dfdt[i]);
		printf("\n");
	}


	SV*	dfdyShell = POPs;

	AV* dfdyRef;

	if (check){
		tempRef = NULL;
		if (SvROK(dfdyShell)){
			tempRef = SvRV(dfdyShell);
			if (SvTYPE(tempRef) != SVt_PVAV) tempRef = NULL;
		}
		if (!tempRef) croak("ERROR: RichGSL::rc_jac - dfdy must be a reference to an array.\n");

		dfdyRef = (AV*)tempRef;
		
		top_index = av_top_index(dfdyRef);
		if (check>1) printf("top_index=%ld\n",top_index);
		if (top_index+1 != num_y) croak("ERROR: RichGSL::rc_jac - delivered (%ld) elements, not (%d) as required\n",top_index+1,num_y);
	} else {
		dfdyRef = (AV*)SvRV(dfdyShell);
	}
	
	for ( int j = 0; j<num_y; ++j ){
		SV* rowShell	= av_shift(dfdyRef);	// An array holds SV's.
		AV* rowRef		= (AV*)SvRV(rowShell);
		for ( int i = 0; i<num_y; ++i ){
			SV* elt	= av_shift(rowRef);	// An array holds SV's.
			if (check && !(SvNOKp(elt) || SvIOKp(elt))) croak("ERROR: RichGSL::rc_jac - detected non-double element\n");
			dfdy[j*num_y+i]	= SvNV(elt);
		}
	}
	
	if (check>1){
		printf("dfdy=\n");
		for ( int j = 0; j<num_y; ++j ){
			for ( int i = 0; i<num_y; ++i ){
				printf("%f,",dfdy[j*num_y+i]);
			}
			printf("\n");
		}
	}
	//croak("Croaked\n");
	
	// Turn off first-pass checking:
	if (check == 1) check = 0;

	FREETMPS;
	LEAVE;

  return status;
}


// The correct, explicit function pointers:
//	int (*func) (double, const double, double, void*)
//	int (*jac) (double, const double, double*, double*, void*)

// For typemaps, see https://perldoc.perl.org/perlxstypemap.html.  The built-in typemap file is perl-x.y.z/lib/x.y.z/ExtUtils/typemap.


AV*
rc_ode_solver(void* func, void* jac, double t0, double t1, int num_steps, int num_y, AV* y, char* step_type, double h_init, double eps_abs, double eps_rel)
{
	// If set to 1, will test details of passing to and from perl in func and jac until jac has run once, then will assume calls will work the same way.
	check = 1;	 // Need to refresh this here.
	
	if (check>1){
		printf("Entering rc_ode_solve\n");
		printf("func=%ld,jac=%ld,\n",*(long*)func,*(long*)jac);
		printf("t0=%f,t1=%f,num_steps=%d,num_y=%d\n",t0,t1,num_steps,num_y);
		printf("step_type=%s,h_init=%f,eps_abs=%f,eps_rel=%f\n",step_type,h_init,eps_abs,eps_rel);
	}
	
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
		croak ("ERROR: RichGSl::rc_ode_solver - unknown step type (%s)\n", step_type);
	}

	gsl_odeiv2_driver * d =
    	gsl_odeiv2_driver_alloc_y_new (&sys, gsl_step_type,
                                  h_init, eps_abs, eps_rel);

	double t		= t0;
	double t_step	= (t1-t0)/num_steps;
	double yt[num_y];
	
	for ( int i = 0; i<num_y; ++i ){
		SV* elt	= av_shift(y);		// An array holds SV's.
		yt[i]	= SvNV(elt);		// I will presume a good double, without checking.
		if (check>1) printf("yt[%d]=%f\n",i,yt[i]);
	}

	AV* resultsAV = newAV();
	
	// Push the initial values:
	AV* rowAV =  newAV();
	av_push(rowAV,newSVnv(t));
	for ( int i = 0; i<num_y; ++i ){
		av_push(rowAV,newSVnv(yt[i]));
	}
	av_push(resultsAV,newRV_inc((SV*)rowAV));
	

	int status = GSL_SUCCESS;
	int j;
	for (j = 1; j <= num_steps; j++)
	{
		if (check>1) printf("Entering j=%d ...\n",j);

		double tj = j*t_step + t0;
		status = gsl_odeiv2_driver_apply (d, &t, tj, yt);
		if (check>1) printf("status=%d\n",status);

		if (status != GSL_SUCCESS)
		{
			printf ("ERROR: RichGSl::rc_ode_solver - return status=%d.\n", status);
			return resultsAV;
		}

		// Push these result doubles into a row array:
		//AV* rowAV =  newAV();
		rowAV =  newAV();
		av_push(rowAV,newSVnv(tj));
		for ( int i = 0; i<num_y; ++i ){
 			av_push(rowAV,newSVnv(yt[i]));
		}
		
		if (check>1){
			printf("t=%f, yt=",tj);
			for ( int i = 0; i<num_y; ++i ) printf("%f,",yt[i]);
			printf("\n");

			SSize_t top_index = av_top_index(rowAV);
			printf("%ld elements loaded into the row array\n",top_index+1);
		}
		

		// Push the row array ref into the results array:
        //SV* newRV_inc((SV*) thing);
        //SV* newRV_noinc((SV*) thing);
		av_push(resultsAV,newRV_inc((SV*)rowAV));
// wrong		av_push(resultsAV,newSVsv((SV*)rowAV));

		if (check>1){
			SSize_t top_index = av_top_index(resultsAV);
			printf("%ld refs are currently loaded into the results array\n",top_index+1);
		}

	}
	
	return resultsAV;
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

