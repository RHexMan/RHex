#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include <rc_ode_solver.h>

#include "const-c.inc"

MODULE = RichGSL		PACKAGE = RichGSL		

INCLUDE: const-xs.inc

AV *
rc_ode_solver(func, jac, t0, t1, num_steps, num_y, y, step_type, h_init, h_max, eps_abs, eps_rel)
	void *	func
	void *	jac
	double	t0
	double	t1
	int	num_steps
	int	num_y
	AV *	y
	char *	step_type
	double	h_init
	double	h_max
	double	eps_abs
	double	eps_rel
