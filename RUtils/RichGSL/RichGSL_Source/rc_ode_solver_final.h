/* rc_ode_solve.h
 * 
 * Copyright (C) 2019, Rich Miller
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or (at
 * your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 */

/* Author:  Rich Miller */

/*
	Created by Rich Miller on 3/15/2019.  This is to replace the call to c_ode_solver() made in PerlGSL::DiffEq::ode_solver.  It is to be part of a self-contained perl static xs module RichGSL::DiffEQ that is identical with the above, except that it calls rc_ode_solver() defined below.
*/


// Put these in place, and change void* to AV* only after
//		h2xs -Oxan RichGSL rc_ode_solve.h -L/sw/lib -lgsl
#include "EXTERN.h"
#include "perl.h"


// Apparently some xs necessary bug prohibits #includes here, at least for the h2xs call (??).

//extern void*
//extern int
extern AV*
rc_ode_solver(void* func, void* jac, double t0, double t1, int num_steps, int num_y, AV* y, char* step_type, double h_init, double eps_abs, double eps_rel);

//gsl_odeiv2_step_type * = translate_step_type (char * step_type);

//#define TESTVAL	4
//extern double	foo(int, long, const char*);
