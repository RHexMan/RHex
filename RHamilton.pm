#!/usr/bin/perl

#############################################################################
## Name:			RHexHamilton.pm
## Purpose:			A Hamilton's Equations 2D integrator specialized for the RHexrod
##                  configuration comprising a linear array of elements (rod and line
##                  segments) moving under the influence of time dependent boundary
##                  conditions, material properties, gravity, and fluid (air or water)
##                  resistence.
## Author:			Rich Miller
## Modified by:	
## Created:			2014/01/30
## Modified:		2017/10/30, 2018/12/31, 2019/1/14
## RCS-ID:
## Copyright:		(c) 2019 Rich Miller
## License:			This program is free software; you can redistribute it and/or
##					modify it under the same terms as Perl itself
#############################################################################

# syntax:  use RHexHamilton;



# BEGIN CUT & PASTE DOCUMENTATION HERE =================================================

# DESCRIPTION:  RSwing is a graphical interface to a program that simulates the motion of a bamboo hex rod, line, leader, and fly during a cast.  The user sets parameters which specify the physical and dimensional properties of the above components as well as the time-motion of the rod handle, which is the ultimate driver of the cast.  The program outputs datafiles and cartoon images that show successive stop-action frames of the components.  Parameter settings may be saved and retrieved for easy project management.

# XXXXX The only significant restriction on the simulation is that the cast is driven and plays out in a single 2-dimensional plane (typically vertical, representing a pure overhead cast).  In addition, the ambient air is assumed to be motionless.

#  RCast is meant to useful for both rod design and for understanding how changes in casting stroke result in different motions of the line and leader.  As in all numerical simulation, the utility is predicting behavior without actually having to build a physical rod, fashion a line and leader, or make casts on a windless day.  In principle, the simulation may be done to any degree of resolution and the integration carried out for any time interval.  However, computer speed sets practical limits.  Perhaps surprisingly, the rod is easy to resolve adequately; it is the line and leader motion that requires most of the computing resource.  Still, with even fairly slow machines and a little patience, you can get enlightening information.

#  The casting stroke may be specified either by setting a number of parameters, or, graphically, by using any of a number of generally available drawing programs to depict a sequence of line segments that represent handle positions in successive frames taken at a fixed rate, and then saving the depiction as an SVD file.  The graphical method allows you to specify any cast at all, but is rather labor intensive.  In calibrating RSwing in the first place, we made slow-motion videos of real casts with a particular rod, line, and leader combination, loaded the individual video frames, one at a time in the Inkscape program, drew a line segment overlying the handle (whose lower and upper ends had been highlighted with yellow tape), and then deleted the frame image, leaving just the line segment.

#  A combination of the parametric and graphical methods is also available.  One can make an SVG file as outlined above, and then parametrically morph the cast, to change the total time duration and the length and direction of the vector connecting the beginning and end locations of the rod butt.

# END CUT & PASTE DOCUMENTATION HERE =================================================


### See "About the calculation" just before the subroutine SetupIntegration() for a discussion of the general setup for the calculation.  Documentation for the individual setup and run parameters may found just below, where the fields of rHexCastRunParams are defined and defaulted.


### NOTE that (because of the short sleep after fork() in RHexPlot) to get window display you may need to manually start x11.  Alternatively, you can try just running this again.  ACTUALLY, THIS SHOULD BE OK NOW.

# Modification history:
#  14/03/12 - Langrangian corrected to include the inertial terms from the kinetic energy into the calculation of the pDots.
#  14/03/19 - Returned to polar dynamical variables for the line, the better to impliment segment length constraint.
#  14/03/28 - Returned to cartesian line dynamical variables.  Previous version stored in Development directory as RHCastPolar.pl
#  14/05/02 - Converted to package to be called from widget and file front ends.
#  14/05/21 - Added postcast drift.
#  14/08/15 - Added video frame capture features.
#  14/08/25 - Added line-tip delayed release mechanism.  Corrected problem with computing nodal spring constants from bamboo elastic modulus.  Relaxed rod nodal spacing.
#  14/09/03 - Restored line damping RATIO as a parameter, while retaining the ability to directly set the damping MODULUS.
#  14/09/13 - Installed SmoothChar to implement partitions of unity.  Added velocity squared damping, fly air damping, and curved line initialization. 
#  14/09/27 - Introduced Calc_pDotsCartForces.
#  14/10/01 - Added leader, removed notion of calc length different from loop length.  Rearranged widget fields, added menubuttons.
#  14/10/21 - Moved some code to RHexCommonPkg.pm
# --- Lots of changes.
#  14/12/22 - Changed loading functions to read file matrix data into pdl's.  Trying to keep use of perl arrays as infrequent and low-level as possible.  Added reading of integration state from rod file.
#  15/01/12 - Refined use of $verbose and made it user setable, substituted pq for print where possible.
#  15/02/06 - Added cut-and-paste documentation, adjusted nav start for save ops.
# --- Lots of changes.
#  17/08/20 - Incorporated PDL's virtual slice mechanism to simplify and possibly speed up data flow in the integration loop.  Corrected two important typo's, one in line tension and one in air drag.  Implemented a more realistic simulation of air drag.
#  17/08/21 - Redid the way the boundary conditions (principally how the handle motion drives the system) to one that I believe is correct.  The previous method was clearly not right, which I understood by examining the case of no rod segs and just one or two line segs.  The new method just pumps potential energy into the system at each timestep, a procedure explicitly allowed by Lanczos analysis.
#  17/09/02 - Previous change in bound condition handling might be in principal ok but led to more difficult integration.  On reflection, my problem with directly applied drive contraints was due to a misunderstanding.  It is correct to simply compute external velocities and add them to the internal ones to construct the KE function, then differentiate per Hamilton to get the dynamic ps, solve for qDots, etc.  On the other hand, a soft constraint to implement tip hold works fine, although one could save a bit of computation time by applying a strict constraint before release start time to temporarily eliminate 2 dynamical variables.
#  17/09/11 - I noticed that with hold implemented via a spring constant on the fly node, increasing the constant made the program run really slowly and didn't do a good job of keeping the fly still.  A small constant did a much better job.  But this makes me think it would be better to just hold the fly via a constraint, eliminating the (dxFly,dyFly) dynamical variable in favor of using the last line segment (between the next-to-last node and the fixed point) to add a force that affects all the pDots in the reduced problem.  I could do this by running the reduced problem up till hold release, and then the full problem, but will try first to see if I can just fake it with the full problem adjusted to keep the fly from moving, while not messing up the movement of the other nodes.
#  17/10/01 - See RHexStatic (17/09/29).  Understood the model a bit better:  the angles theta are the dynamical variables and act at the nodes (hinges), starting at the handle top and ending at the node before the tip.  The bending at these locations creates torques that tend to straighten the angles (see GradedSections()).  The masses, however, are properly located at the segment cg's, and under the effect of gravity, they also produce torques at the nodes.  In equilibrium, these two sets of torques must cancel.  Note that there is no need for the masses to be in any particular configuration with respect to the hinges or the stretches - the connection is established by the partials matrix, in this case, dCGQs_dqs (in fact, also d2CGQs_d2thetas for Calc_pDotsKE). There remains a delicacy in that the air drag forces should more properly be applied at the segment surface resistance centers, which are generally slightly different from the segment cgs.  However, to avoid doubling the size of the partials matrices, I will content myself with putting the air drags at the cg's.
#  17/10/08 - For a while I believed that I needed to compute cartesian forces from the tension of the line on the guides.  This is wrong.  Those forces are automatically handled by the constraints.  However, it does make sense to take the length of the section of line between the reel and the first line node (say a mark on the line, always outside the rod tip) as another dynamical variable.  The position of the marked node in space is determined by the seg length and the direction g by the two components of the initial (old-style) line segment.  To first approximation, there need not be any mass associated with the line-in-guides segment since that mass is rather well represented by the extra rod mass already computed, and all the line masses outboard cause the new segment to have momentum.  What might be gained by this extra complication is some additional shock absorbing in the line.

#  17/10/30 - Modified to use the ODE solver suite in the Gnu Scientific Library.  PerlGSL::DiffEq provides the interface.  This will allow the selection of implicit solvers, which, I hope, will make integration with realistic friction couplings possible.  It turns out to be well known that friction terms can make ODE's stiff, with the result that the usual, explicit solvers end up taking very small time steps to avoid going unstable.  There is considerable overhead in implicit solutions, especially since they require jacobian information.  Providing that analytically in the present situation would be a huge problem, but fortunately numerical methods are available.  In particular, I use RNumJac, a PDL version of Matlab's numjac() function that I wrote.

#  19/01/01 - RHexHamilton split off from RHexCast to isolate the stepper part of the code.  The remaining code became the setup and caller, still called RHexCast.  A second caller, RSink was created to run the stepper in submerged sink line mode.  This code handles both.

#  19/01/14 - Stripper mode added to this code, to handle the case where, after an interval of sinking, the line is stripped in through the tip guide.  The implementation draws the first line (inertial) node in toward the rod tip by reducing (as a function of time) the nominal length of the initial segment while simultaneously reducing its mass and adjusting its nominal (CG) diameter, and (perhaps) the relative CG location.  Once the seg len becomes rather short (but no so short that it messes up the computational inverse), this code returns control to the caller, which then takes note of the final cartesian location of the initial inertial node, records as it will, reduces the number of line nodes by 1, removes the associated (dx,dy) dynamical variables, and calls InitHamilton($Arg_T0,$Arg_Dynams0,$X0,$Y0), causing a partial reset of all the dynamical variables here.  The caller then makes a new call to the ODE solver.

### TO DO:
# Get TK::ROText to accept \r.
# Add hauling and wind velocity.


# Compile directives ==================================
package RHamilton;

# See https://www.perlmonks.org/?node_id=526948  This seems to be working, the export push DEBUG up the use chain.  I'm assuming people are right when they say the interpreter just expunges the constant false conditionals.

use warnings;
use strict;

use Exporter 'import';
our @EXPORT = qw(DEBUG Init_Hamilton Get_T0 Get_dT Get_TDynam Get_DynamsCopy Calc_Driver Calc_VelocityProfile Get_HeldTip DEfunc_GSL DEjac_GSL DEset_Dynams0Block DE_GetStatus DE_GetCounts JACget AdjustHeldSeg_HOLD Get_ExtraOutputs);

#if (DEBUG){print "ARRGH\n";}


use Time::HiRes qw (time alarm sleep);
use Switch;
use File::Basename;
use Math::Spline;
use Math::Round;

# We need our own copies of all the PDL stuff.  Easier than explicitly exporting it from RHexCommon.

use PDL;
    # Import main PDL module (see PDL.pm for equivalents).  In particular, imports PDL::Math, which redefines many POSIX math functions.  To get the original, call POSIX::aFunction.

use PDL::NiceSlice;
use PDL::AutoLoader;    # MATLAB-like autoloader.
use PDL::Options;     # Good to keep in mind. See RLM.

#use RRungeKutta;   # R's modification that allows early return.
#use Try::Tiny;
#use PerlGSL::DiffEq ':all';
    # PerlGSL is a Collection of Perlish Interfaces to the Gnu Scientific Library.  PerlGSL::DiffEq solves ODEs using GSL v1.15+
#use RDiffEq;
use RNumJac;

use RCommon;
use RPrint;
use RPlot;
#use RPlot qw(PlotMat);
#use RPlot;

#use constant EPS => 2**(-52);
#my $EPS = EPS;


# Run params --------------------------------------------------------------


# ABOUT THE CALCULATION =================================================================

# The scheme below was significantly modified on 17/08/21, and then unmodified 17/09/02

# I treat the rod as made up by connected fixed length segments, spring hinged at their ends.  The hinges are the rod nodes.  There are $numRodNodes of these.  The node at index 0 is the handle top node and that at index $numRodNodes-1 is the rod tip node.  The entire cast is driven by external constraints applied to the handle, in particular specifying the handle top node X and Y coordinates and the handle cartesian theta direction measured relative to vertical (driverX,driverY,driverTheta).  The rod is allowed to flex at its upper handle node.  The rod does not flex at its tip node.  The rod dynamical variables are the hinge angles (dthetas) starting with the upper handle node and running to the node below the rod tip.

# The line is also described by a vector of nodes.  The line segments come before their respective nodes, so the first line segment (line index 0) runs from the rod tip node to the first line node, and there is no segment beyond the last line node.  The line is set up to behave like an ideal string, each segment has a nominal length, and we impose an elastic force that tends to keep the segment length no greater than nominal, but allows it to be anything less.  It turns out to be best to work with the line in local cartesian coordinates, that is, the line dynamical variables are dxs and dys, the differences between the cartesian coordinates of adjacent nodes.  There are $numLineNodes.

# The ordered list of rod nodes, followed by the ordered list of line nodes comprises the system nodes.  The dynamical variables are listed as (dthetas) followed by (dxs) followed by (dys).  The inertial nodes (those whose masses come into play) run from the first node above the handle top to the line tip node (the fly).

# At any time, the state of the dynamical variables fix the cartesian coordinates of all the nodes.  I use initial lower-case letters for dynamical variables and initial capitals for cartesian ones.  I list all the X coords first, followed by all the Y coords.  The values of the dynamical variables fix those of the cartesian, and the dynamical variables together with their velocities fix the cartesian velocities.

# Fixed masses are associated with each of the nodes, and as is usual in classical mechanics, the dynamics play out due to interactions between these masses and forces (potential and dissipative) associated with the dynamical variables.

# VISCOUS (velocity related) damping, due both to rod and line material physical properties and to fluid friction play a significant part in real world casting dynamics.  Thus, damping must be built into the computational model as well.  Lanczos' treatment of Hamiltonial Mechanics, which forms the basis for our calculations here, does not deal with frictional losses.  So, I am winging it.

# The situation for the ROD INTERNAL FRICTION seems most clear cut:  We can think of it as modifying the geometric power fiber stretching and compression mechanism that generates the local bending spring constant ($rodKsNoTip).  (See the comments in RHexCommon.pm just before the declaration of $hex2ndAreaMoment, and in SetupIntegration() below, before the declaration of the local variable $rodSectionMultiplier.)  At a given rod node, the theta partial of the total potential energy is just the value of $rodKsNoTip at the node times theta there, which is the usual Hook's Law force, and this force is therefore the bending energy's contribution to the change in the nodal conjugate momentum.  Internal friction in, and between adjacent, power fibers gives a thetaDot-dependent adjustment to the local elastic force.  I argue that, at a given time, globally (and dynamically), the system cannot distinguish between these two generation MECHANISMs for the local force.  That is, the system's change in (conjugate) momentum is the same for a nodal elastic and an equal valued nodal viscous force.  Thus it is ok to simply add the effects when computing pDotRodLocal.  At this level of calculation, the system doesn't distinguish "holonomic" from "non-holonomic" forces.  Pushing on this a bit, the viscous force correction produces a correction to pDots, which, at the next iteration step corrects ps, and therefore qDots, and consequently, corrects the total system KE to account for the energy lost to friction.

# Another approach I tried was just modifying the qDots directly (kinematics), but this seem clearly wrong since it doesn't account for the configurations and magnitudes of the masses being moved.

# The bending and stretching drags are "laminar" (well ordered?), and so ought to be linear in velocity.  Line air resistance, ought to have some linear and some quadratic.  Figure our approximate Reynolds number.


# Previously, I tried to adjust the nodal friction factors to result in critical damping at each node.  In fact, doing that correctly would require recomputing the spatial distribution of outboard masses at each time.  But even working to a time-independent approximation is actually NOT FAIR for BAMBOO rods!  This is because the fiber damping should be just a property of the material itself, which we have taken to be homogenous along the rod.  The nodal damping should be determined by the fiber damping, the diameter, and a form factor.

# The above discussion of internal friction at the rod nodes also applies to the LINE nodes when the line segments are STRETCHED to or beyond their nominal lengths.  I have modelled that situation with a one-sided damped harmonic oscillator.  Again, both the restoring spring and damping forces are local, residing in the line segment, and again they should simply add to modify the corresponding nodal pDot.  Here too, it is at least SOMEWHAT UNFAIR to tweak the nodal damping factors individually toward critical damping, although the line manufacturer could in fact do that.  The final result would still be imperfect due to variable lure mass and also due to variable line configuration during the progression of the cast.

# What about fluid damping?  It is MORE COMPLEX, since it's not just a local effect.  BUT line normal friction is obviously important, even critical, in the presence of gravity.

# We can see how to handle fluid friction by inspection of the calculation of the effect of gravity.  Gravity is useful in that the manipulation is completely legitimate (taking the qDot partial of the potential energy in the Hamiltonian formulation) while clearly separating the roles of the cartesian force and the geometric leverage in generating a contribution to pDot.  To wit:  For each configuration variable q associated with some node, each outboard node contributes to the PE by its cartesian height Y' times its weight W'.  The partial of this wrt q is dQs_dqs(q,Y')*W'.  The factor on the right is the cartesian force, and that on the left is pure geometry that gives the "leverage" of that force has in generating a time-change in the conjugate momentum p.  If we rotated the whole cartesian system before doing our calculation,  we would have dQs_dqs(q,X')*WX' + dQs_dqs(q,Y')*WY' where WX' and WY' are the components of the weight force vector in the X and Y directions, respectively.


# For fluid friction, the outboard nodal force points in some direction (frequently rather normal to the line or rod at that node) and has a magnitude that is a multiple (depending on the local characteristic sizes) of some function of the outboard nodal velocity.  The last formula of the previous paragraph is operative, where now WX' and WY' are the components of the frictional force.  This should be so since the mass dynamics of the whole system should have no way of knowing or caring what particular physical phenomenon (gravity or friction) generated the outboard nodal force. 


#  If the velocity acts linearly, we speak of "viscous" drag.  However, more generally, the velocity enters quadratically, and is well modelled by multiplying V^2 by a "drag coefficient" that is a function of the Reynolds number. Typical line normal Reynolds numbers in our casts are less than 100, frequently much less.  In this region, the drag coefficient is linearly decreasing in log-log coordinates.


## OLD   The rod nodes come first, then the line nodes.  The dynamical variables for the rod are the nodal deflection angles stored in the variable thetas.  These are exterior angles, small for small curvature, with positive angles deflecting the rod to the right going toward tip.  It is critical for correct modeling that the line not support compression, while at the same time being extensible only up to a fixed length.  Thus I can't simply constrain the line segment lengths as I do the rod.  I could extend the theta scheme to the line, and let these angles together with the individual segment lengths be the line dynamical variables.  However, since the segment lengths must be allowed to pass through zero and come out the other side, the singularity of polar coordinates at r=0 would require a lot of special handling.  It seems easier to simply use relative cartesian coordinates to locate the line nodes.  My scheme is to have the (dys,dxs) be the coordinates of the next node in the system whose origin is the current node.

#### WARNING:  The RungeKutta integrator works with 1-dimensional (ie, flat) vectors!!!  However, I want the matrix algebra to look the usual way, so I am always transposing and flattening, which is inexpensive since PDL charges just for tiny header changes.

# Variables here set from args to SetupHamilton():
my ($mode,
    $gravity,$rodLength,$actionLength,
    $numRodNodes,$init_numLineNodes,
    $init_segLens,$init_segCGs,$init_segCGDiams,
    $init_segWts,$init_segKs,$init_segCs,
    $init_flyNomLen,$init_flyNomDiam,$init_flyWt,
    $dragSpecsNormal,$dragSpecsAxial,
    $segFluidMultRand,
    $driverXSpline,$driverYSpline,$driverThetaSpline,$driverOffsetTheta,
    $frameRate,$driverTotalTime,$tipReleaseStartTime,$tipReleaseEndTime,
    $T0,$Dynams0,$dT,
    $runControlPtr,$programmerParamsPtr,$loadedStateIsEmpty,
    $profileText,$bottomDepthFt,$surfaceVelFtPerSec,$halfVelThicknessFt,
    $surfaceLayerThicknessIn,
    $sinkInterval,$stripRate);


my ($tDynam,$dynams);    # My global copy of the args the stepper passes to DE.
my $numRodSegs;

my ($DE_status,$DE_ErrMsg);

# Working copies (if stripping, cut down from the initial larger pdls, and subsequently, possibly with first seg readjusted in time):
my ($numLineNodes,$numLineSegs);
my ($segLens,$segCGs,$segCGDiams,
    $segWts,$segKs,$segCs,
    $rodKsNoTip,$rodCsNoTip,$lineSegKs,$lineSegCs,
    $flyNomLen,$flyNomDiam,$flyWt);

my ($surfAccelStartTime,$surfAccelEndTime,$surfAccelDuration,$adjustedSurfaceVelFtPerSec);
$surfAccelStartTime = 0;
$surfAccelEndTime = 0;
$surfAccelDuration = $surfAccelEndTime - $surfAccelStartTime;

my ($gravAccelStartTime,$gravAccelEndTime,$gravAccelDuration,$g);
$gravAccelStartTime = 0;
$gravAccelEndTime = 0;
$gravAccelDuration = $gravAccelEndTime - $gravAccelStartTime;

my ($rodSegLens,$lineSegNomLens,$init_lineSegNomLens);
my ($CGWts,$CGQMasses,$CGs,$CGQMassesDummy1,$lineLowerTriPlus,$line_pDotsStdGravity);
my ($calculateFluidDrag,$airOnly,$CGBuoys);
my $holding;
my ($stripping,$stripStartTime);
#my ($stripX0,$stripY0);
my ($thisSegStartT,$lineSegNomLensFixed,$lineSegWtsFixed);
my ($HeldSegLen,$HeldSegK,$HeldSegC);


sub Init_Hamilton { my $verbose = 1?$verbose:0;
    $mode = shift;
    
    if ($mode eq "initialize"){
        
        my ($Arg_gravity,$Arg_rodLength,$Arg_actionLength,
            $Arg_numRodNodes,$Arg_numLineNodes,
            $Arg_segLens,$Arg_segCGs,$Arg_segCGDiams,
            $Arg_segWts,$Arg_segKs,$Arg_segCs,
            $Arg_flyNomLen,$Arg_flyNomDiam,$Arg_flyWt,
            $Arg_dragSpecsNormal,$Arg_dragSpecsAxial,
            $Arg_segFluidMultRand,
            $Arg_driverXSpline,$Arg_driverYSpline,$Arg_driverThetaSpline,$Arg_driverOffsetTheta,
            $Arg_frameRate,$Arg_driverTotalTime,$Arg_tipReleaseStartTime,$Arg_tipReleaseEndTime,
            $Arg_T0,$Arg_Dynams0,$Arg_dT,
            $Arg_runControlPtr,$Arg_programmerParamsPtr,$Arg_loadedStateIsEmpty,
            $Arg_profileText,$Arg_bottomDepthFt,$Arg_surfaceVelFtPerSec,$Arg_halfVelThicknessFt,
            $Arg_surfaceLayerThicknessIn,
            $Arg_sinkInterval,$Arg_stripRate) = @_;
        
        PrintSeparator ("Initializing stepper code",2);
        
        $gravity                    = $Arg_gravity;
        $rodLength                  = $Arg_rodLength;
        $actionLength               = $Arg_actionLength;
        $numRodNodes                = $Arg_numRodNodes;
        $init_numLineNodes          = $Arg_numLineNodes;
        $init_segLens               = $Arg_segLens->copy;
        $init_segCGs                = $Arg_segCGs->copy;
        $init_segCGDiams            = $Arg_segCGDiams->copy;
        $init_segWts                = $Arg_segWts->copy;
        $init_segKs                 = $Arg_segKs->copy;
        $init_segCs                 = $Arg_segCs->copy;
        $init_flyNomLen             = pdl($Arg_flyNomLen);
        $init_flyNomDiam            = pdl($Arg_flyNomDiam);
        $init_flyWt                 = pdl($Arg_flyWt);
        $dragSpecsNormal            = $Arg_dragSpecsNormal;
        $dragSpecsAxial             = $Arg_dragSpecsAxial;
        $segFluidMultRand           = $Arg_segFluidMultRand;
        $driverXSpline              = $Arg_driverXSpline;
        $driverYSpline              = $Arg_driverYSpline;
        $driverThetaSpline          = $Arg_driverThetaSpline;
        $driverOffsetTheta          = $Arg_driverOffsetTheta;
        $frameRate                  = $Arg_frameRate;
        $driverTotalTime            = $Arg_driverTotalTime;
        $tipReleaseStartTime        = $Arg_tipReleaseStartTime;
        $tipReleaseEndTime          = $Arg_tipReleaseEndTime;
        $T0                         = $Arg_T0;
        $Dynams0                    = $Arg_Dynams0->copy;
        $dT                         = $Arg_dT;
        $runControlPtr              = $Arg_runControlPtr;
        $programmerParamsPtr        = $Arg_programmerParamsPtr;
        $loadedStateIsEmpty         = $Arg_loadedStateIsEmpty;
        $profileText                = $Arg_profileText;
        $bottomDepthFt              = $Arg_bottomDepthFt;
        $surfaceVelFtPerSec         = $Arg_surfaceVelFtPerSec;
        $halfVelThicknessFt         = $Arg_halfVelThicknessFt;
        $surfaceLayerThicknessIn    = $Arg_surfaceLayerThicknessIn;
        $sinkInterval               = $Arg_sinkInterval;
        $stripRate                  = $Arg_stripRate;
        
        
        # I will always "initialize" as though there is no stripping or holding, and then let subsequent calls to "restart_stripping" and "restart_holding" deal with those states.  This lets me have the caller do the appropriate adjustments to $Dynams0 (so $dynams).
        
        $stripping  = 0;
        $holding    = 0;
        
        if (defined($sinkInterval)){
            if (!defined($stripRate)){die "ERROR:  In stripping mode, both sinkInterval and stripRate must be defined.\n"}
                $stripStartTime = $T0 + $sinkInterval;
                if ($verbose>=3){pq($sinkInterval,$stripRate,$T0,$stripStartTime)}
        }
        

        if (!defined($tipReleaseStartTime) or !defined($tipReleaseEndTime)){
            # Turn off release delay mechanism:
            $tipReleaseStartTime    = $T0 - 1;
            $tipReleaseEndTime      = $T0 - 0.5;
        }
        
        $adjustedSurfaceVelFtPerSec = $surfaceVelFtPerSec;
        $g                          = $gravity;

        # Initialize other things directly from the passed params:
        
        if ($numRodNodes == 0){$numRodNodes = 1};
        # Set to 0 or 1 to indicate no rod.  If there is a rod, includes handle top node and tip, so at least 2 nodes.  Otherwise, the single rod node is the tip, which is not inertial.
        #pq($nRodNodes);
        $numRodSegs     = $numRodNodes - 1;
 
        $numLineNodes   = $init_numLineNodes;
        $numLineSegs    = $numLineNodes;
        
        $airOnly = (!defined($profileText))?1:0;    # Strange that it requires this syntax to get a boolean.
        
        # Set hold before adjusting for slow startup. ???
        # No hold unless there is at least one line node.
        
        if ($surfAccelStartTime < $T0) {
            $T0 += $surfAccelStartTime;
        }
        
        $calculateFluidDrag = any($dragSpecsNormal->glue(0,$dragSpecsAxial));
        
        DE_InitCounts();
        DE_InitExtraOutputs();
        
        #JAC_FacInit();
    }
    
    elsif ($mode eq "restart_stripping") {
        my ($Arg_restartT,$Arg_numLineNodes,$Arg_Dynams,$Arg_beginningNewSeg) = @_;
        
        PrintSeparator ("In stripper mode, re-initializing stepper code,",3);
        
        $numLineNodes   = $Arg_numLineNodes;
        $numLineSegs    = $numLineNodes;
        my $restartT    = $Arg_restartT;
        $Dynams0        = $Arg_Dynams->copy;
        
        #JAC_FacInit($Arg_JACfac);
        
        #$time  = $restartT;  # Just to get us started.  Will be reset in each call to DE.
        
        if ($Arg_beginningNewSeg){$thisSegStartT = $restartT}
        
        if (!$numLineNodes){die "ERROR:  Stripping only makes sense if there is at least one (remaining) line node.\n"}
        
        # Set these here from old (previously returned) $Dynams values, before reinitializing:  OLD IDEA
        #my ($tXs,$tYs) = Calc_Qs($restartT,$Arg_Dynams0_old,0);
        
        #$stripX0    = $tXs($numRodNodes);
        #$stripY0    = $tYs($numRodNodes);
        # 1 sic, its the returned location of the node that will be at the rod tip during this run.  It should be very close to the rod tip now.
        
        $stripping  = ($stripRate > 0 and $restartT >= $stripStartTime)?1:0;
        if ($verbose>=3){pq($stripStartTime,$restartT,$thisSegStartT,$Arg_beginningNewSeg,$stripping)}
    }
    elsif ($mode eq "restart_holding") {
        my ($Arg_restartT,$Arg_numLineNodes,$Arg_Dynams,$Arg_holding) = @_;
        
        ## This is how I conceive of tip holding: The two tip segment variables (original dxs(-1),dys(-1)) are no longer dynamical, but become dependent on all the remaining (inboard) ones, since the tip outboard node (the fly) is fixed in space, and the tip inboard node is determined by all the inboard variables.  However, the remaining variables are still influenced by the tip segment in a number of ways:  The segment cg is still moved by the inboard variables, and the amount is exactly half of the motion of the tip inboard node, since the fly node contributes nothing.  This contributes both inertial and frictional forces. The fly mass ceases to have any effect.  Finally, the stretching of the tip segment contributes elastic and damping forces.
        
        ## Thus, I implement holding this way:  Remove the original tip variables from $dynams.  Remove the fly mass, but treat the tip seg mass as a new fly mass, but keep its location in the (no longer dynamic) tip segment.  This affects the cartesian partials, which are modified explicitly. Internal and external velocities act on this cg.
        
        PrintSeparator ("In holding mode, re-initializing stepper code,",3);
        
        $numLineNodes           = $Arg_numLineNodes;
        $numLineSegs            = $numLineNodes;
        $Dynams0                = $Arg_Dynams->copy;
        
        if ($holding == 0 and $Arg_holding == 1){           # Begin holding tip.
            Set_HeldTip($T0);
            $holding    = 1;
        } elsif ($holding == 1 and $Arg_holding == -1){     # Begin releasing tip.
            $holding = -1;
        } elsif ($holding == -1 and $Arg_holding == 0){     # Begin free tip.
            $holding = 0;
        }
        
        # Putting the above scheme in place:
        
    }
    else {die "Unknown mode.\n"}
    
    # Setup the shared storage:
    Init_WorkingCopies();
    Init_DynamSlices();
    Init_HelperPDLs();
    Init_HelperSlices();
    
    if (!$numRodSegs){Calc_CartesianPartials_NoThetas()}    # Needs the helper PDLs and slices to be defined
    
    if ($mode eq "initialize"){
        ## More initialization that needs to be done after the Init_'s above.
        
        if ($loadedStateIsEmpty){Set_ps_From_qDots($T0)}
        # This will load the $ps section of $dynams.

        $Dynams0 = $dynams;
    }
    

    DEset_Dynams0Block($Dynams0->list);   # To setup call to JACInit just below.
    #JAC_OtherInits();
    JACInit();

    $DE_status          = 0;
    $DE_ErrMsg          = "";
    

}


sub Init_WorkingCopies {
    
    PrintSeparator("Making working copies",3);
    
    #pq($numRodSegs,$init_numLineNodes,$numLineNodes);

    my $iRods   = $numRodSegs ? sequence($numRodSegs) : zeros(0);
    my $iLines;
    if ($init_numLineNodes){
        if (!$stripping and !$holding){
            $iLines = $numRodSegs + sequence($numLineNodes);
        } elsif ($stripping) {
            my $numRemovedNodes = $init_numLineNodes-$numLineNodes;
            $iLines = ($numRodSegs+$init_numLineNodes-$numLineNodes) + sequence($numLineNodes);
        } elsif ($holding){ # OK for both 1 and -1; $numLineNodes was set appropriately in restart.
            $iLines = $numRodSegs + sequence($numLineNodes);
        } else {    # stripping and holding
           die "ERROR: For now, cast stripping (ie, hauling) is not implemented.\n"
        }
        
    } else { $iLines = zeros(0)}
    my $iKeeps  = $iRods->glue(0,$iLines);
    #pq($iRods,$iLines,$iKeeps);

    $segLens    = $init_segLens->dice($iKeeps)->copy;
    $segCGs     = $init_segCGs->dice($iKeeps)->copy;
    $segCGDiams = $init_segCGDiams->dice($iKeeps)->copy;
    $segWts     = $init_segWts->dice($iKeeps)->copy;
    $segKs      = $init_segKs->dice($iKeeps)->copy;
    $segCs      = $init_segCs->dice($iKeeps)->copy;
 
    if ($verbose>=3){pq($segLens,$segCGs,$segCGDiams,$segWts,$segKs,$segCs)}


    my $iiKeeps = $numRodSegs ? sequence($numRodSegs) : zeros(0);
    # WARNING:  New variable since dice should not make a copy of the indices until they go out of scope.
    #pq($iiKeeps);

    $rodKsNoTip = $init_segKs->dice($iiKeeps);
    $rodCsNoTip = $init_segCs->dice($iiKeeps);

    $rodSegLens = $segLens->dice($iiKeeps);
    
    if (DEBUG and $verbose>=4){pq($rodKsNoTip,$rodCsNoTip,$rodCsNoTip)}

    my $iiiKeeps = $numLineSegs ? $numRodSegs + sequence($numLineSegs) : zeros(0);
    # WARNING:  New variable since dice should not make a copy of the indices until they go out of scope.
    #pq($iiiKeeps);
   
    $lineSegNomLens = $segLens->dice($iiiKeeps);
    my $lineSegWts  = $segWts->dice($iiiKeeps);
    $lineSegKs      = $segKs->dice($iiiKeeps);
    $lineSegCs      = $segCs->dice($iiiKeeps);

    if (DEBUG and $verbose>=4){pq($rodSegLens,$lineSegNomLens)}

    # Make some copies to be fixed for this run:
    if ($stripping == 1){
        $lineSegNomLensFixed    = $lineSegNomLens->copy;
        $lineSegWtsFixed        = $lineSegWts->copy;
    }
    
    
    #$lineSegNomLens0        = $lineSegNomLens->copy;
    #$lineFirstSegNomLen0    = $lineSegNomLens(0)->sclr;
    #$lineFirstSegWt0        = $lineSegWts(0)->sclr;
    
    #if (DEBUG and $verbose>=4){pq($lineFirstSegNomLen0,$lineFirstSegWt0)}
   
    if ($holding == 1){
        $HeldSegLen = $init_segLens(-1);
        $HeldSegK   = $init_segKs(-1);
        $HeldSegC   = $init_segCs(-1);
    }
    
    # Implement the conceit that when holding == 1 the last seg specs are attributed to the fly, and athe calculation is done without the original last seg's dynamical veriables.  Weights at all inertial nodes for use in Calc_pDotsGravity().  The contribution to the forces from gravity for the line is independent of the momentary configuration and so can be computed in advance here.
    $flyNomLen      = ($holding == 1) ? $init_segLens(-1) : $init_flyNomLen;
    $flyNomDiam     = ($holding == 1) ? $init_segCGDiams(-1) : $init_flyNomDiam;
    $flyWt          = ($holding == 1) ? $init_segWts(-1) : $init_flyWt;
    
    $CGWts          = $segWts->glue(0,$flyWt);

    my $CGmasses    = $massFactor*$CGWts;
    $CGQMasses      = append($CGmasses,$CGmasses);    # Corresponding to X and Y coords of all segs and the fly pseudo-seg.
    if ($verbose>=3){pq $CGQMasses}
    
    my $flyCG   = ($holding == 1) ? $init_segCGs(-1) : pdl(1);
    $CGs    = $segCGs->glue(0,$flyCG);
    
    if ($verbose>=3){pq($holding,$CGWts,$CGQMasses,$flyCG,$CGs)}
        
    my $CGForcesStdGravity    = -$gravity*$CGWts;
    if ($verbose>=3){pq($CGForcesStdGravity)};
    
    if ($numLineSegs) {
        
        # Prepare "extended" lower tri matrix used in constructing dCGQs_dqs in Calc_CartesianPartials():
        my $extraRow        = ($holding == 1) ? zeros($numLineSegs) : ones($numLineSegs);
        $lineLowerTriPlus   = LowerTri($numLineSegs,1)->glue(1,$extraRow);
        if ($verbose>=3){pq($holding,$lineLowerTriPlus)}
        # Extra row for fly weight.
        
        if ($gravity){
            #pq($CGWts,$idx0);
            $extraRow    = (1-$CGs(-1))*ones($numLineSegs);
            my $tLower   = LowerTri($numLineSegs,1)->glue(1,$extraRow);
            $line_pDotsStdGravity = ((-$CGWts($numRodSegs:-1)) x $tLower)->flat;
            # Negative, positive g force always points down.
            if ($verbose>=3){pq($tLower,$line_pDotsStdGravity)}
        }
    }

    
    if (!$airOnly){
        
        # No holding in sink implentation.
        
        my $tDiams   = $segCGDiams->glue(0,$flyNomDiam);
        my $tLens    = $segLens->glue(0,$flyNomLen);
        my $tVols    = ($pi/4) * $tDiams**2 * $tLens;
        $CGBuoys            = $tVols*$waterOzPerIn3;
        if (DEBUG and $verbose>=3){pq($tDiams,$tLens,$tVols)}

        my $CGForcesStdBuoyancy = $gravity*$CGBuoys;
        if ($verbose>=3){pq($CGForcesStdBuoyancy)};
        
        my $CGForcesStdNet     = $CGForcesStdGravity + $CGForcesStdBuoyancy;
        if ($verbose>=2 and ($mode eq "initialize")){pq($CGForcesStdNet)};
    }
}
    

my $smallNumber = 1e-8;
my $smallStrain = 1e-6;
# 0.01 gave good results, with strains typically less than that.  0.001, however, gives visibly undistinguishable results.  With 0.0000001, very small observable differences, but note line damping = 100.  With damping off, there was considerable difference, lots of mid-cast slack segments, and especially tip zinging.  And with ss = 0.01, damping off, very much like the same small strain with damping 100; only the tinyest bit faster; and not any apparent wobble.
my $KSoftRelease = 100; # Used only for soft release.


# Use the PDL slice mechanism in the integration loop to avoid as much copying as possible.  Except where reloaded (using .=); must be treated as read-only:

# Declare the dynamical variables and their useful slices:
my ($nRodNodes,$nThetas,$nLineNodes,$nINodes,$nQs,$nCGs,$nCGQs,$nqs);
my $dynamDots;
my ($idx0,$idy0);
my ($qs,$dthetas,$dxs,$dys);
my ($ps,$dthetaps,$dxps,$dyps);
my ($qDots,$dthetaDots,$dxDots,$dyDots);

my ($dXs,$dYs,$dRs,$uXs,$uYs,$uLineXs,$uLineYs,
    $lineStretches,$lineStrains,$tautSegs);  # Reloaded in Calc_dQs().
my ($Xs,$Ys);   # Reloaded in Calc_Qs().
my ($thetaPartialsMask);
my $pDots; # Reloaded in Calc_pDots().


sub Init_DynamSlices {
    
    ## Initialize counts, indices and useful slices of the dynamical variables.
    
    PrintSeparator ("Setting up the dynamical slices",3);
    if ($verbose>=3){pq($Dynams0)};
    

    $nRodNodes  = $numRodNodes;
    $nThetas    = $nRodNodes-1;  # Hinges at rod handle top node and above, except none at rod tip node (no stiffness there!).  The inertial CGs are in the segment above each node.
    
    #pq($numLineNodes);
    $nLineNodes = $numLineNodes;  # Nodes outboard of the rod tip node.  The cg for each of these is inboard of the node.  However, the last node also is the location of an extra quasi-segment that represents the mass of the fly.
    $nINodes    = $nThetas + $nLineNodes; # All inertial nodes.  This comprises the rod nodes ABOVE the handle top node (which is NOT inertial, but constrained), including the rod tip node.
    $nQs        = 2*$nINodes;
    $nCGs       = $nINodes + 1;     # Includes and extra CG for the fly quasi-segment.
    $nCGQs      = 2*$nCGs;
    
    $nqs        = $nThetas + 2*$nLineNodes;
        # All dthetas (incl handle top, but not rod tip), dxs, dys.

    if ($verbose>=3){pq($nRodNodes,$nThetas,$nLineNodes,$nINodes,$nQs,$nCGs,$nCGQs,$nqs)}
    
    $dynams     = $Dynams0->copy->flat;    # Initialize our dynamical variables, reloaded at the beginning of DE().
    
    if ($dynams->nelem != 2*$nqs){die "ERROR: size mismatch with \$Dynams0.\n"}

    $dynamDots  = zeros($dynams);   # Set as output of DE().

    $idx0       = $nThetas;
    $idy0       = $idx0+$nLineNodes;
    
    $qs         = $dynams(0:$nqs-1);
    if ($verbose>=3){pq($dynams,$qs)}
    
    #$dthetas    = $dynams(0:$idx0-1);
    $dthetas    = ($idx0)?$dynams(0:$idx0-1):zeros(0);
        # The usual PDL notation doesn't work correctly here.
    $dxs        = $dynams($idx0:$idy0-1);
    $dys        = $dynams($idy0:$nqs-1);
    
    $ps         = $dynams($nqs:2*$nqs-1);
    if ($verbose>=3){pq($ps)}

    
    # Only possibly used in report:
    #$dthetaps   = $ps(0:$idx0-1);
    $dthetaps   = ($idx0)?$ps(0:$idx0-1):zeros(0);
    # The usual PDL notation doesn't work correctly here.
    $dxps       = $ps($idx0:$idy0-1);
    $dyps       = $ps($idy0:$nqs-1);
 
    $qDots      = zeros($qs);
        # Correctly initialized for empty loaded state, unused otherwise until reloaded in Calc_qDots().
    #$dthetaDots = $qDots(0:$idx0-1);
    $dthetaDots = ($idx0)?$qDots(0:$idx0-1):zeros(0);
    $dxDots     = $qDots($idx0:$idy0-1);
    $dyDots     = $qDots($idy0:$nqs-1);
    
    ($dXs,$dYs,$dRs,$uXs,$uYs) = map {zeros($nINodes)} (0..4);
    $uLineXs       = $uXs($nThetas:-1);
    $uLineYs       = $uYs($nThetas:-1);

    
    $pDots  = zeros($ps);

}


my ($d2Xs_d2thetas_extended,$d2Ys_d2thetas_extended);
my ($dXs_dqs_extended,$dYs_dqs_extended);
my ($d2CGQs_d2thetas,$dCGQs_dqs,$dQs_dqs);
my $extCGVs;

sub Init_HelperPDLs { my $verbose = 1?$verbose:0;
    
    ## Initialize pdls that will be referenced by slices.
    
    PrintSeparator("Initializing helper PDLs",3);

    # Storage for $d2Qs_d2thetas and $dQs_dqs extended to enable interpolating for cgs partials:
    $d2Xs_d2thetas_extended     = zeros($nThetas,$nINodes+2,$nThetas);
    $d2Ys_d2thetas_extended     = zeros($nThetas,$nINodes+2,$nThetas);
        # Plus 1 for the fly, and plus one more for averaging.
    
    $dXs_dqs_extended           = zeros($nqs,$nINodes+2);
    $dYs_dqs_extended           = zeros($nqs,$nINodes+2);
        # Ditto.
    
    # Storage for the nodes partials:
    $dQs_dqs                    = zeros($nqs,$nQs);
   
    # Storage for the cgs partials:
    $d2CGQs_d2thetas            = zeros($nThetas,$nCGQs,$nThetas);
    $dCGQs_dqs                  = zeros($nqs,$nCGQs);
    
    $extCGVs                    = zeros($nCGQs);
    
    # WARNING and FEATURE:  dummy acts like slice, and changes when the original does!  I make use of this in AdjustFirstSeg_STRIPPING().
    $CGQMassesDummy1            = $CGQMasses->dummy(1,$nqs);

    # Prepare the mask for the trigonometric matrices used for constucting the rod elements in dQsdThetas and their thetas derivatives:
    $thetaPartialsMask          = zeros($nThetas,$nThetas,$nThetas);
    for (my $ii=0;$ii<$nThetas;$ii++) {
        $thetaPartialsMask(0:$ii,$ii:-1,$ii) .= 1;
    }
    
}


my ($d2Xs_d2thetas,$d2Ys_d2thetas);
my ($d2RodXs_d2thetas,$d2RodYs_d2thetas);

my ($dXs_dqs,$dYs_dqs);

#my ($dQs_dqs,$d2Qs_d2thetas);


sub Init_HelperSlices { my $verbose = 1?$verbose:0;
    
    PrintSeparator("Initializing helper slices",3);
    
    # Shorthand for the nodal partials:
    if ($idx0){
        $d2Xs_d2thetas      = $d2Xs_d2thetas_extended(:,1:$nINodes,:);
        $d2Ys_d2thetas      = $d2Ys_d2thetas_extended(:,1:$nINodes,:);
        
        $d2RodXs_d2thetas   = $d2Xs_d2thetas_extended(:,1:$nThetas,:);
        $d2RodYs_d2thetas   = $d2Ys_d2thetas_extended(:,1:$nThetas,:);

        if ($verbose>=3){pqInfo($d2Xs_d2thetas,$d2Ys_d2thetas,$d2RodXs_d2thetas,$d2RodYs_d2thetas)}
    }
    
    $dXs_dqs            = $dXs_dqs_extended(:,1:$nINodes);
    $dYs_dqs            = $dYs_dqs_extended(:,1:$nINodes);
 
    if ($verbose>=3){pqInfo($dXs_dqs,$dYs_dqs)}
    
    if ($idx0){$dRs(0:$nThetas-1)   .= $rodSegLens;}   # Unchanged during integration.
    
}


sub Get_T0 {
    return $T0;
}

sub Get_dT {
    return $dT;
}

sub Get_TDynam   {
    return $tDynam
}

sub Get_DynamsCopy {
    return $dynams->copy;
}



my ($isRK0,$goodStep,$goodStepSize);

# Keep this function self contained.
sub Calc_Qs { my $verbose = 0?$verbose:0;
    my ($tt, $tqs, $includeHandleButt) = @_;
    
    ## Return the cartesian coordinates Xs and Ys of all the rod and line NODES.  These are used for plotting and reporting.
    
    # A key benefit of an entirely relative scheme is that changes in the dynamical variables at a node only affect outboard nodes, and that changes in the thetas change nodal cartesian positions and velocities in the same way.
    
    # Except if we need to calculate fluid drag, this function is not used during the integration, just for reporting afterward.  It returns cartesian coordinates for ALL the nodes, including the driven handle node.  If includeButt is true, it prepends the butt coord.
    
    my ($driverX,$driverY,$driverTheta) = Calc_Driver($tt);
    
    my ($dthetas,$dxs,$dys) = Unpack_qs($tqs);
    #    pq($dthetas,$dxs,$dys);
    #pq($driverX,$driverY,$driverTheta);
    
    my $thetas = cumusumover($dthetas);
    $thetas += $driverTheta;
    
    my $dXs = pdl($driverX)->glue(0,$rodSegLens*sin($thetas));
    my $dYs = pdl($driverY)->glue(0,$rodSegLens*cos($thetas));
    
    $dXs = $dXs->glue(0,$dxs);
    $dYs = $dYs->glue(0,$dys);
#pq($dXs,$dYs);
    
    my $Xs = cumusumover($dXs);
    my $Ys = cumusumover($dYs);
    
    if ($includeHandleButt){
        my $handleLength = $rodLength-$actionLength;
        $Xs = ($Xs(0) - $handleLength*sin($driverTheta))->glue(0,$Xs);
        $Ys = ($Ys(0) - $handleLength*cos($driverTheta))->glue(0,$Ys);
    }
    
    if ($verbose>=3){print "Calc_Qs:\n Xs=$Xs\n Ys=$Ys\n"}
    return ($Xs,$Ys);
}



# DYNAMIC VARIABLE HANDLING ===========================================================

sub Unpack_qs {     # Safe version, with ->copy
    my ($qs) = @_;
    
    my $dthetas = ($nThetas)?$qs(0:$idx0-1)->copy:zeros(0);
    my $dxs     = zeros(0);
    my $dys     = zeros(0);
    if ($nLineNodes){
        $dxs     = $qs($idx0:$idy0-1)->copy;
        $dys     = $qs($idy0:$nqs-1)->copy;
    }
   
    return ($dthetas,$dxs,$dys);
}


sub Extract_qsLine {     # Safe version, with ->copy
    my ($qs) = @_;
    
    my $dxs     = $qs($idx0:$idy0-1)->copy;
    my $dys     = $qs($idy0:$nqs-1)->copy;
    
    return ($dxs,$dys);
}


# COMPUTING DYNAMIC DERIVATIVES ===========================================================

my ($driverX,$driverY,$driverTheta,$driverXDot,$driverYDot,$driverThetaDot);


sub Calc_Driver { my $verbose = 0?$verbose:0;
    my ($t) = @_;   # $t is a PERL scalar.
    
    if ($t < 0) {$t = 0}
    if ($t > $driverTotalTime) {$t = $driverTotalTime}
    
    $driverX        = $driverXSpline->evaluate($t);
    $driverY        = $driverYSpline->evaluate($t);
    $driverTheta    = ($nThetas)?$driverThetaSpline->evaluate($t) + $driverOffsetTheta:0;
    
    if ($t == 0 or $t == $driverTotalTime) {
        $driverXDot = 0;
        $driverYDot = 0;
        $driverThetaDot = 0;
    
    } else {
        my $dt = ($t<=$driverTotalTime/2) ? 0.001 : -0.001;
        $dt *= $driverTotalTime;     # Must be small compared to integration dt's.

        $driverXDot = $driverXSpline->evaluate($t+$dt);
        $driverXDot = ($driverXDot-$driverX)/$dt;

        $driverYDot = $driverYSpline->evaluate($t+$dt);
        $driverYDot = ($driverYDot-$driverY)/$dt;

        if ($nThetas){
            $driverThetaDot = $driverThetaSpline->evaluate($t+$dt) + $driverOffsetTheta;
            $driverThetaDot = ($driverThetaDot-$driverTheta)/$dt;
        } else {$driverThetaDot = 0}
    }

    if ($verbose>=3){print "Calc_Driver($t): hx=$driverX, hy=$driverY, htheta=$driverTheta\n hxd=$driverXDot, hyd=$driverYDot, hthetad=$driverThetaDot\n"}
    return ($driverX,$driverY,$driverTheta,$driverXDot,$driverYDot,$driverThetaDot);
}



sub Calc_dQs { my $verbose = 1?$verbose:0;
    # Needs $qs, $driverTheta.

#    print "In Calc_dQs\n";
    
    ## Calculate the rod and line segments as cartesian vectors from the dynamical variables.
#    pq($dthetas);
    if ($nThetas){
        my $thetas = cumusumover($dthetas);
        $thetas += $driverTheta;
    #    pq($thetas,$rodSegLens);
        
        $dXs(0:$nThetas-1)  .= $rodSegLens*sin($thetas);
        $dYs(0:$nThetas-1)  .= $rodSegLens*cos($thetas);
    #    $dRs(0:$nThetas-1)  .= $rodSegLens;
    #    pq($dXs,$dYs);
    }

    if ($nLineNodes){
        my $tLineRs     = sqrt($dxs**2 + $dys**2);
        $dRs($idx0:-1)  .= $tLineRs;
        # Line dxs, dys were automatically updated when y was, but ...
    #    pq($dRs);

        $dXs($idx0:-1)     .= $dxs;
            # I would have expected to automatically inherit changes from y, but it seems not.
        $dYs($idx0:-1)     .= $dys;    # Ditto.

    #    pq($dXs,$dYs);
    #    pq($dxs,$dys);

        $lineStretches  = ($tLineRs-$lineSegNomLens)->flat;
        $lineStrains    = ($lineStretches/$lineSegNomLens)->flat;
        $tautSegs       = $lineStrains >= 0;
        if (DEBUG and $verbose>=4){pq($lineStretches,$lineStrains,$tautSegs)}
    }
    
    # Compute X and Y components of the outboard pointing unit vectors along the segments:
    $uXs .= $dXs/$dRs;     # convert any nan's to zeros.
    $uYs .= $dYs/$dRs;
    my $ii = which(!$dRs);
    if (!$ii->isempty){
        $uXs($ii) .= 0;
        $uYs($ii) .= 0;
    }
    
#    pq($uXs,$uYs);
    
    #    $uLineXs .= $uXs($nRodNodes:-1);     shouldn't have to do anything.
    # $uLineYs .= $uYs($nRodNodes:-1);
#    pq($uLineXs,$uLineYs);
    
    if (DEBUG and $verbose>=4){print "Calc_dQs (dXs=$dXs\n dYs=$dYs\n"}
    #    return ($dXs,$dYs);
}


my ($CGXs,$CGYs);

# Used only in computing fluid drag.
sub Calc_CGQs { my $verbose = 0?$verbose:0;
    
    # Return the cartesian coordinates Xs and Ys of all the NODES.
    my $Xs = pdl($driverX)->glue(0,cumusumover($dXs));
    my $Ys = pdl($driverY)->glue(0,cumusumover($dYs));
    
    my $extendedXs = $Xs->glue(0,$Xs(-1));
    my $extendedYs = $Ys->glue(0,$Ys(-1));
    
    $CGXs = $CGs*$extendedXs(0:-2)+(1-$CGs)*$extendedXs(1:-1);
    $CGYs = $CGs*$extendedYs(0:-2)+(1-$CGs)*$extendedYs(1:-1);
    
    if ($verbose>=3){print "Calc_CGQs:\n";pq($Xs,$Ys,$CGXs,$CGYs)}
    return ($CGXs,$CGYs);
}



#??? work on a lower triangular matrix multiplication and inversion (maybe LU decomp).

sub Calc_CartesianPartials { my $verbose = 1?$verbose:0;
    #    my ($qs) = @_;
    
    ## Compute first and second partials of the nodal cartesian coordinates with respect to the dynamical variables.
    
    ## Per the operational procedure (comment 17/10/01), after computing partials at nodes, make and adjusted copy that gives partials at the seg (including tip quasi-seg) cg's.
    
    # From our definitions we see that changes in (x0,y0) and in any of the (dxs,dys) just parallel translate everything outboard, making all those partials identical, and so may be copied.  Only partials wrt the thetas require complicated computation.
    
    #   In computing thetaDots from ps we need the matrix of partial derivatives of the cartesian velocities with respect to the thetaDots.  We call that matrix dQs_dthetas.  (Actually, this is used only in Calc_pDotsKE!!)
    
    # NOTE - IMPORTANT!!  Because our line variables are cartesian differences, changes in any (rod) theta move all the line nodes by parallel translation, which they inherit from the motion of the rod tip.
    
    # the partial of the Xs wrt x0 (=X0) is 1 and that of Ys is zero.
    # similarly for partials wrt to y0.  = so (  ones($nINodes),zeros($nINodes), etc.
    
    # Remember my convention for ordering the dynamic variables is x0,y0,theta0,otherThetas,dxs,dys, but the cartesian coordinates are allXs,allYs.
    
    # I have lumped in theta0 for convenience.  It produces non-zero derivatives and second derivatives for cartesian points not X0 and Y0, but these cancel out to give no contribution to KE.  (Think about this)
    
    #pq($qs,$ps,$dthetas);
    
    my $thetas = cumusumover($dthetas);
    $thetas += $driverTheta;
    #pq($thetas);
    
    # The second partials for the thetas cols are accumulated and passed on:
    my $tSin_thetaColsCum = zeros($nThetas,$nThetas);
    my $tCos_thetaColsCum = zeros($nThetas,$nThetas);
    
    # Loop down over the thetas, starting at the last one.  Build theta cols for the rod theta second partials:
    for (my $ii=$nThetas-1;$ii>=0;$ii--) {
        
        my $tMask = $thetaPartialsMask(:,:,$ii)->reshape($nThetas,$nThetas);
        my $tSin_thetaCols = sin($thetas($ii))*$tMask;      # Could do "which" here too.
        my $tCos_thetaCols = cos($thetas($ii))*$tMask;
        
        # Second partial with respect to theta:
        $tSin_thetaColsCum += $rodSegLens*$tSin_thetaCols;
        $tCos_thetaColsCum += $rodSegLens*$tCos_thetaCols;
        
        $d2RodXs_d2thetas(:,:,$ii) .= -$tSin_thetaColsCum;
        $d2RodYs_d2thetas(:,:,$ii) .= -$tCos_thetaColsCum;
        # Actually loading $d2Xs_d2thetas, $d2Ys_d2thetas.
        
    }
    #pq($d2RodXs_d2thetas,$d2RodYs_d2thetas);
    
    # Do the required row duplications (could also use Dummy()):
    if ($nLineNodes) {
        $d2Xs_d2thetas(:,$nThetas:$nINodes-1,:) .= $d2RodXs_d2thetas(:,$nThetas-1,:);
        $d2Ys_d2thetas(:,$nThetas:$nINodes-1,:) .= $d2RodYs_d2thetas(:,$nThetas-1,:);
    }
    #pq($d2Xs_d2thetas_extended,$d2Ys_d2thetas_extended);
    
    if ($holding != 1){
        $d2Xs_d2thetas_extended(:,-1,:) .= $d2Xs_d2thetas(:,-1,:);
        $d2Ys_d2thetas_extended(:,-1,:) .= $d2Ys_d2thetas(:,-1,:);
    } else {
        $d2Xs_d2thetas_extended(:,-1,:) .= 0;   # Possibly unnecessary, but just to make sure.
        $d2Ys_d2thetas_extended(:,-1,:) .= 0;
    }
    #    if (DEBUG and $verbose>=4){pq($d2Qs_d2thetas)}

    #pq($holding,$CGs);
    #pq($d2Xs_d2thetas_extended,$d2Ys_d2thetas_extended);
    
    # Interpolate to get CG values:
    my $CGs_tr = $CGs->transpose;
    $d2CGQs_d2thetas .=
    ((1-$CGs_tr)*$d2Xs_d2thetas_extended(:,0:-2,:) + $CGs_tr*$d2Xs_d2thetas_extended(:,1:-1,:))
    ->glue(1,(1-$CGs_tr)*$d2Ys_d2thetas_extended(:,0:-2,:) + $CGs_tr*$d2Ys_d2thetas_extended(:,1:-1,:));
    # If you're going to assign everything, might as well glue.  I can imagine an implementation that does this just as efficiently.
    if (DEBUG and $verbose>=5){pq($d2CGQs_d2thetas)}
    
    
    # Construct the first partials from the index 0 second partials:
    $dXs_dqs_extended(0:$nThetas-1,:)   .= -$d2Ys_d2thetas_extended(:,:,0)->reshape($nThetas,$nINodes+2);
    $dYs_dqs_extended(0:$nThetas-1,:)   .= $d2Xs_d2thetas_extended(:,:,0)->reshape($nThetas,$nINodes+2);
    
    #pq($dXs_dqs_extended,$dYs_dqs_extended);
    if ($nLineNodes){
        $dXs_dqs_extended($idx0:$idy0-1,$nThetas+1:-1)    .= $lineLowerTriPlus;
        $dYs_dqs_extended($idy0:-1,$nThetas+1:-1)         .= $lineLowerTriPlus;
        # +1 because of the zeros first row in extended.  The size of $lineLowerTriPlus was set properly when it was created.
    }
    #pq($dXs_dqs_extended,$dYs_dqs_extended);
    
    # Effects of hold already accounted for.
    
    #pq($dXs_dqs,$dYs_dqs);
    
    $dQs_dqs .= $dXs_dqs->glue(1,$dYs_dqs);
    # If you're going to assign everything, might as well glue.  I can imagine an implementation that does this just as efficiently.
    #$dQs_dqs(:,0:$nINodes-1)    .= $dXs_dqs;
    #$dQs_dqs(:,$nINodes:-1)     .= $dYs_dqs;
    #pq($dQs_dqs);
    
    # Interpolate to get CG values::
    
    #!!! prob last row should be zero in extended.  I was duplicating last position derivs, then taking any cg for fly. but now should use zero as last and take real seg cg.
 
    #pq($holding,$CGs);
    
    $dCGQs_dqs .=
    ((1-$CGs_tr)*$dXs_dqs_extended(:,0:-2) + $CGs_tr*$dXs_dqs_extended(:,1:-1))->
        glue(1,(1-$CGs_tr)*$dYs_dqs_extended(:,0:-2) + $CGs_tr*$dYs_dqs_extended(:,1:-1));
    #pq($dCGQs_dqs);
    
    if (DEBUG and $verbose>=4){print "In calc partials: ";pq($dCGQs_dqs)}
    #if($holding){die}
    
    return ($dCGQs_dqs,$d2CGQs_d2thetas,$dCGQs_dqs);
}

sub Calc_CartesianPartials_NoThetas { my $verbose = 0?$verbose:0;
    #    my ($qs) = @_;
    
    ## The returns are all constant during the integration, so should call this from init.
    
    ## Compute first partials of the nodal cartesian coordinates with respect to the dynamical variables.  NOTE that the second partials are not needed in this case.
    
    # the partial of the Xs wrt x0 (=X0) is 1 and that of Ys is zero.
    # similarly for partials wrt to y0.  = so (  ones($nINodes),zeros($nINodes), etc.
    
    # $holding is always 0 here.

    #pq($dXs_dqs_extended,$dYs_dqs_extended);
    if ($nLineNodes){
        $dXs_dqs_extended($idx0:$idy0-1,1:-1)    .= $lineLowerTriPlus;
        $dYs_dqs_extended($idy0:-1,1:-1)         .= $lineLowerTriPlus;
        # (+)1 because of the zeros first row in extended.  The size of $lineLowerTriPlus was set properly when it was created.
    }
    #pq($dXs_dqs_extended,$dYs_dqs_extended);
    
    # Effects of hold already accounted for.
    
    #pq($dXs_dqs,$dYs_dqs);
    
    $dQs_dqs .= $dXs_dqs->glue(1,$dYs_dqs);
    # If you're going to assign everything, might as well glue.  I can imagine an implementation that does this just as efficiently.
    #$dQs_dqs(:,0:$nINodes-1)    .= $dXs_dqs;
    #$dQs_dqs(:,$nINodes:-1)     .= $dYs_dqs;
    #pq($dQs_dqs);
    
    # Interpolate:
    my $CGs_tr = $CGs->transpose;
    
    $dCGQs_dqs .=
    ((1-$CGs_tr)*$dXs_dqs_extended(:,0:-2) + $CGs_tr*$dXs_dqs_extended(:,1:-1))
    ->glue(1,(1-$CGs_tr)*$dYs_dqs_extended(:,0:-2) + $CGs_tr*$dYs_dqs_extended(:,1:-1));
    #pq($dCGQs_dqs);
    
    if ($verbose>=3){print "In calc partials (no thetas): ";pq($dCGQs_dqs,$dQs_dqs)}
    return ($dCGQs_dqs,$dQs_dqs);
}


sub Calc_ExtCGVs { my $verbose = 0?$verbose:0;
    
    ## External velocity is nodal motion induced by driver motion, path and orientation, but not by the bending at the zero node.  NOTE that the part of the external V's contributed by the change in driver direction is gotten from the first column of the dQs_dqs matrix (which is the same as the first column of the $dQs_dthetas matrix), in just the same way that the internal contribution of the bending of the 0 node is.
    
    if (DEBUG and $verbose>=4){print "\nCalc_ExtVs ----\n"}
    #pq($driverXDot,$driverYDot,$driverThetaDot)}
    
    $extCGVs .= ($driverXDot*ones($nCGs))->glue(0,$driverYDot*ones($nCGs));
    
    # driverThetaDot only comes into play if there is at least one rod segment.
    if ($nThetas){
        $extCGVs += $driverThetaDot * $dCGQs_dqs(0,:)->flat;
    }
    #!!! the adjustment to $dCGQs_dqs should do this automatically!
    
    if ($verbose>=3){pq $extCGVs}
    return $extCGVs;
}


my $fwd;    # Make these generally available.
my $inv;

sub Calc_qDots { my $verbose = 0?$verbose:0;
    #    my ($ps) = @_;
    
    ## Solve for qDots in terms of ps from the definition of the conjugate momenta as the partial derivatives of the kinetic energy with respect to qDots.  We evaluate the matrix equation      qDots = ((Dtr*bigM*D)inv)*(ps - Dtr*bigM*Vext).
    
    # !!!  By definition, p = ∂/∂qDot (Lagranian) = ∂/∂qDot (KE) - 0 = ∂/∂qDot (KE).  Thus, this calculation is not affected by the definition of the Hamiltonian as Hamiltonian = p*qDot - Lagrangian, which comes later.  However, the pure mathematics of the Legendre transformation then gives qDot = ∂/∂p (H).
    
    
    if (DEBUG and $verbose>=4){print "\nCalc_qDots ---- \n"}
    
    my $dMCGQs_dqs_Tr = $CGQMassesDummy1*($dCGQs_dqs->transpose);
    if ($verbose>=3){pq $dMCGQs_dqs_Tr}

    $fwd = $dMCGQs_dqs_Tr x $dCGQs_dqs;
    if ($verbose>=3){pq $fwd}
    
    $inv = $fwd->inv;
    if ($verbose>=3){pq $inv}
    
    if (DEBUG and $verbose>=5){
        my $dd = det($inv);
        my $test = $inv x $fwd;
        pq($dd,$test);
    }
    
    my $ext_ps_Tr = $dMCGQs_dqs_Tr x $extCGVs->transpose;
    my $ps_Tr = $ps->transpose;
    my $pDiffs_Tr = $ps_Tr - $ext_ps_Tr;
    
    if (DEBUG and $verbose>=4){
        my $tMat = $ps_Tr->glue(0,$ext_ps_Tr)->glue(0,$pDiffs_Tr);
        print "cols(ps,ext_ps,p_diffs)=$tMat\n";
    }
    
    $qDots .= ($inv x $pDiffs_Tr)->flat;
    
    if ($verbose>=3){pq $qDots}
    return $qDots;
}




my $CGQDots;  # Calc_pDotsKE uses $QDotsExt separately.

sub Calc_CGQDots { my $verbose = 0?$verbose:0;
    
    if ($verbose>=3){print "\nCalc_CGQDots ----\n"}
    
    my $intCGVs = ($dCGQs_dqs x $qDots->transpose)->flat;
    #pq($intCGVs,$holding);

    
    $CGQDots = $extCGVs + $intCGVs;
    # Because of the adjustments to the tip in Calc_ExtCGVs, the held tip velocities here zero.
    
    #pq($extCGVs);
    
    if ($verbose>=3){pq $CGQDots}
    return $CGQDots;
}


my $QDots;  # For reporting.

sub Calc_QDots { my $verbose = 0?$verbose:0;
    
    if (DEBUG and $verbose>=4){print "\$Calc_CGQDots ----\n"}
    
    my $extVs = ($driverXDot*ones($nINodes))->glue(0,$driverYDot*ones($nINodes));
    
    # driverThetaDot only comes into play if there is at least one rod segment.
    if ($nRodNodes>1){
        $extVs += $driverThetaDot * $dQs_dqs(0,:)->flat;
    }
    
    $QDots = $extVs + ($dQs_dqs x $qDots->transpose)->flat;
    # Because of the adjustments to the tip in Calc_ExtCGVs and Calc_CartesianPartials(), the held tip velocities here automatically zero.
    
    if ($verbose>=3){pq $QDots}
    return $QDots;
}


sub Calc_pDotsKE { my $verbose = 0?$verbose:0;
    #    my ($qDots) = @_;
    
    ## Compute the kinetic energy's contribution to pDots.
    
    # !!! Using the correct, general definition of Hamiltonian = p*qDot - Lagrangian, where L = cartesian KE - PE, we get the contribution to pDot is -∂/∂q (H) = +∂/∂q (KE) - ∂/∂q (PE) since there is no dependence of p*qDot on q.  Thus this function needs to return the plus sign!!!  All the other contributions to pDot come from the PE, and get a minus sign.
    
    # BUT, worry about whether the frictional terms belong in KE or PE.
    
    # NOTE that because of the very particular form of the LINE dynamical variables (differences of adjacent node cartesian coordinates), the KINETIC energy does not depend on these variables (dxs, dys) themselves, but only on their derivatives (dxDots, dyDots).
    
    # Thus, from the Hamiltonian formulation, we have NO CONTRIBUTION from the kinetic energy to the time derivatives of the conjugate momenta (pDots) corresponding to the LINE variables.  Consequently this function returns pDots only for the rod variables (thetas).  Of course, because of line elasticity and gravity, the line variables DO supply a POTENTIAL ENERGY contribution to the pDots
    
    
    if (DEBUG and $verbose>=4){print "\nCalc_pDotsKE ----\n"}
    #die "make sure I get the right sign here  Should be negative of dKE/dq, and include ext v's properly";
    
    # Figure the cartesian momentum:
    my $Ps = $CGQMasses * $CGQDots;
    # pq($Ps);
   # pqInfo($Ps);
    #    pq($qDots);
    
    my $WsMat = zeros($nThetas,2*$nCGs);
    
    for (my $ii=0;$ii<$nThetas;$ii++) {
        $WsMat($ii,:) .= $d2CGQs_d2thetas(:,:,$ii)->reshape($nThetas,2*$nCGs)
        x $dthetaDots->transpose;       # Squeeze below unsafe if 1 rod seg.
    }
    #pq($WsMat);
    my $pDotsKE = ($Ps x $WsMat)->flat;       #--
    ### 17/09/02 I added minus sign here, since pDot = - ∂KE/∂q.  On 17/09/05 changed back since I decided that was wrong.  See comment above.
    
    if ($verbose>=3){
        my $tMat = $Ps->transpose->glue(0,$WsMat);
        print "cols(Ps,Ws)=$tMat\n\n";
    }
    
    if ($verbose>=5){pq $pDotsKE}
    return $pDotsKE;
}


sub Calc_pDotsGravity { my $verbose = 1?$verbose:0;
    #    my ($qs) = @_;
    
    if (DEBUG and $verbose>=4){print "\nCalc_pDotsGravity ----\n"}
    
    my $pDotsGravity = zeroes($pDots);
    
    if ($gravity) {
        
        my $CGForcesGravity    = -$g*$CGWts;   # Sic, on slow start, $g will be less than $gravity.

        if ($nThetas){
            # Start with the rod cgs (configuration dependent):
            $pDotsGravity(0:$nThetas-1) .=
            ($CGForcesGravity x $dCGQs_dqs(0:$nThetas-1,$nCGs:-1))->flat;
            # These apply only to the Y coordinates!!  But, everybody outboard contributes to the change of a node's conjugate momentum.  $CGForcesGravity already contains the negative sign.
        }
        
        # Append the line nodes (configuration independent, affects only y coords):
        if ($nLineNodes){
            
            $pDotsGravity(-$nLineNodes:-1) .= $g*$line_pDotsStdGravity;
            # Already includes negative sign.
        }
    }
    
    if (DEBUG and $verbose>=4){pq $pDotsGravity}
    return $pDotsGravity;
} 


my $rDotsLine;  # For reporting./Users/richmiller/Active/Code/PERL/RHexrod/RHexHamilton.pm

sub Calc_pDotsLine { my $verbose = 0?$verbose:0;
    # Uses ($qs,$qDots) = @_;
    # Calc_dQs() must be called first.

    ## Enforce line segment constraint as a one-sided, damped harmonic oscillator.
    
    if (!$nLineNodes){return (zeros(0),zeros(0))};

    if (DEBUG and $verbose>=4){print "\nCalc_pDotsLine ----\n"}
    
    # Done correctly, maybe I don't need smoothing at hooks law transition.  BUT maybe I do, since line behavior is apparently numerically much less stable than rod behavior.
    #    my $prDotsK = -$tautSegs*$lineStretches*$lineSegKs;
    my $smoothTauts = 1-SmoothChar($lineStrains,0,$smallStrain);
    my $prDotsK     = -$smoothTauts*$lineStretches*$lineSegKs;
    #pq($lineStrains,$smoothTauts,$prDotsK);
    
    # Figure the RATE of stretching:
    $rDotsLine = ($dxDots*$uLineXs+$dyDots*$uLineYs);

    # Use LINEAR velocity damping, since the stretches should be slow relative to the cartesian line velocities. BUT, is this really true?:
    #    my $prDotsC = -$tautSegs*$rDotsLine*$lineSegCs;
    my $prDotsC = -$smoothTauts*$rDotsLine*$lineSegCs;

    
    # The forces act only along the segment tangent directions:
    my $pDotsLineK  = ($prDotsK*$uLineXs)->glue(0,$prDotsK*$uLineYs);
    my $pDotsLineC  = ($prDotsC*$uLineXs)->glue(0,$prDotsC*$uLineYs);
    
    return ($pDotsLineK,$pDotsLineC,$prDotsK(0));
}


my ($XDiffHeld,$YDiffHeld,$RDiffHeld,$stretchHeld,$strainHeld,$tautHeld);
my ($XTip0,$YTip0);

sub Calc_pDotsTip_HOLD { my $verbose = 0?$verbose:0;
    my ($t,$tFract) = @_;   # $t is a PERL scalar.
    
    ## For times less than start release, make the tension force on the last line segment (with its original, small, spring constant) depend on the distance between the next-to-last node and the fixed tip point.  Implement as cartesian force acting on that node. The original (dxs(-1),dys(-1) are not dynamical variables in this case.
    
    # For times between start and end release, call Calc_pDotsTip_SOFT_RELEASE() instead.
    
    
    my $pDots_HOLD = zeros($ps);
    if ($tFract!=1){ return $pDots_HOLD}
    
    if ($verbose>=3){print "Calc_pDotsTipHold: t=$t,ts=$tipReleaseStartTime, te=$tipReleaseEndTime, fract=$tFract\n"}
    
    # Must be sum over everything, since original last seg not dynamic, and so is not included in the (dXs,dYs) computed in holding mode.
    my $XDynamLast = $driverX + sumover($dXs);
    my $YDynamLast = $driverY + sumover($dYs);
    if ($verbose>=3){pq($XDynamLast,$YDynamLast,$XTip0,$YTip0)}
   
    $XDiffHeld  = $XTip0-$XDynamLast;
    $YDiffHeld  = $YTip0-$YDynamLast;
    $RDiffHeld  = sqrt($XDiffHeld**2 + $YDiffHeld**2);

    
    $stretchHeld     = $RDiffHeld-$HeldSegLen;
    $strainHeld      = $stretchHeld/$HeldSegLen;
    $tautHeld        = $strainHeld >= 0;
    
    #    pq($stretchHeld,$strainHeld,$tautHeld);
 
    if ($tautHeld){
        $pDots_HOLD = $HeldSegK * $stretchHeld *
                                (   ($XDiffHeld/$RDiffHeld) * $dQs_dqs(:,$nINodes-1)->flat +
                                    ($YDiffHeld/$RDiffHeld) * $dQs_dqs(:,-1)->flat );
        # Sic. $dQs_dqs since we want contribution from a node.  Plus sign because the force points toward the fly from the previous node.
    }
    
    ### ??? shouldn't there be a contribution from $HeldSegC??
    
    if ($verbose>=3){pq($pDots_HOLD)}

    return $pDots_HOLD;
}

my ($tKSoft,$XDiffSoft,$YDiffSoft,$RDiffSoft,$stretchSoft);

sub Calc_pDotsTip_SOFT_RELEASE { my $verbose = 0?$verbose:0;
    my ($t,$tFract) = @_;   # $t is a PERL scalar.
    
    ## Large cartesian force before release start, no force after release end, applied to the tip node.
    
    my $pDots_SOFT_RELEASE = zeros(0);
    if ($tFract>=1 or $tFract<=0){ return $pDots_SOFT_RELEASE}
    
    if ($verbose>=3){print "Calc_pDotsTip_SOFT_RELEASE: t=$t,ts=$tipReleaseStartTime, te=$tipReleaseEndTime, fract=$tFract\n"}
    
    $tKSoft = $KSoftRelease * $tFract;
    ## The contribution to the potential energy from forces holding the fly in place affect all the dynamical variables, since a change in to any of them holding the rest fixed moves the fly.
    #my $tipEnergy = $tKSoft/2 * (($Xs(-1)-$XTip0)**2 + ($Ys(-1)-$YTip0)**2);
    # -dtipEnergyX/ddynvar = -$tKSoft * ($Xs(-1)-$XTip0) * dXs(-1)/ddynvar.
    
    my $XTip = $driverX + sumover($dXs);
    my $YTip = $driverY + sumover($dYs);
    if ($verbose>=3){pq($XTip,$YTip,$XTip0,$YTip0)}
    
    $XDiffSoft  = $XTip0-$XTip;
    $YDiffSoft  = $YTip0-$YTip;
    $RDiffSoft  = sqrt($XDiffSoft**2 + $YDiffSoft**2);
    
    $stretchSoft     = $RDiffSoft;
    
    $pDots_SOFT_RELEASE = $tKSoft * $stretchSoft *
        (   ($XDiffSoft/$RDiffSoft) * $dQs_dqs(:,$nINodes-1)->flat +
            ($YDiffSoft/$RDiffSoft) * $dQs_dqs(:,-1)->flat  );
        # Sic. $dQs_dqs since we want contribution from a node.
    
    if ($verbose>=3){pq($pDots_SOFT_RELEASE)}
    return $pDots_SOFT_RELEASE;
}

# =============  New, water drag

my $isSubmergedMult;    # Include smooth transition in the water surface layer.

sub Calc_VelocityProfile { my $verbose = 0?$verbose:0;
    my ($CGYs,$typeStr,$bottomDepthFt,$surfaceVelFtPerSec,$halfVelThicknessFt,$surfaceLayerThicknessIn,$plot) = @_;
    
    # To work both in air and water.  Vel's above surface (y=0) (air) are zero, below the surface from the water profile.  Except, I make a smooth transition at the water surface over the height of the surface layer thickness, given by the $isSubmergedMult returned.  This will then be used in setting the buoyancy contribution to pDots, which, I hope, will make the integrator happier.
    
    
#### put in $surfaceLayerThicknessIn
    
    my $D   = $bottomDepthFt*12;         # inches
    my $v0  = $surfaceVelFtPerSec*12;   # inches/sec
    my $H   = $halfVelThicknessFt*12;   # inches
    
    # Set any pos CGYs to 0 (return them to the water surface) and any less than -depth to -depth.
    $CGYs = $CGYs->copy;
    my $ok = $D+$CGYs>=0;   # Above the bottom
    $CGYs = $ok*$CGYs+(1-$ok)*(-$D);    # If below the bottom, place at bottom
 
    
    $isSubmergedMult = $CGYs <= 0;
    
    my $vels;
    if ($v0){
        switch ($typeStr) {
            
            case "profile - const" {
                $vels = $v0 * ones($CGYs);
            }
            case "profile - lin" {
                my $a = $D/$v0;
                $vels = ($D+$CGYs)/$a;
            }
            case "profile - exp" {
               # y = ae**kv0, y= a+D+1+Y (Yneg). a=H**2/(D-2H), k = ln((D+a)/a)/v0.
                my $a = $H**2/($D-2*$H);
                my $k = log( ($D+$a)/$a )/$v0;
                $vels = log( ($a+$D+$CGYs)/$a )/$k;
                # CGYs are all non-pos, 0 at the surface.  Depth pos.
            }
        }
    }else{
        $vels = zeros($CGYs);
    }
    
    # If not submerged, make velocity zero except in the surface layer
    my $isSubmergedMult = SmoothChar($CGYs,0,$surfaceLayerThicknessIn);
    #pq($surfaceMults);
    $vels *= $isSubmergedMult;
    #pq($vels);
    
    if (defined($plot) and $plot){
        my $plotMat = ($CGYs->glue(1,$vels))->transpose;
        
        PlotMat($plotMat(-1:0,:),0,"Velocity(in/sec) vs Depth(in)");
        #PlotMat($plotMat,0,"Depth(in) vs Velocity(in/sec)");
    }
    
    if($verbose>=3){pq($CGYs,$vels,$isSubmergedMult)}
    return ($vels,$isSubmergedMult);
}


sub Calc_SegDragForces { my $verbose = 0?$verbose:0;
    my ($speeds,$isSubmergedMult,$type,$segCGDiams,$segLens) = @_;
    ## Usually, just segs, not fly pseudo-seg, but make a separate call (normal only) with nominal diam and len for the fly.
    
     #pq($mult,$power,$min);
    my ($mult,$power,$min);
    switch ($type) {
        case "normal" {
            $mult   = $dragSpecsNormal(0);
            $power  = $dragSpecsNormal(1);
            $min    = $dragSpecsNormal(2);
        }
        case "axial" {
            $mult   = $dragSpecsAxial(0);
            $power  = $dragSpecsAxial(1);
            $min    = $dragSpecsAxial(2);
        }
    }
    #pq($mult,$power,$min);
    
    my $kinematicViscosityFluid
        = $isSubmergedMult*$kinematicViscosityWater + (1-$isSubmergedMult)*$kinematicViscosityAir;
    my $fluidBlubsPerIn3
        = $isSubmergedMult*$waterBlubsPerIn3 + (1-$isSubmergedMult)*$airBlubsPerIn3;
    
    #pq($speeds,$isSubmergedMult,$kinematicViscosityFluid,$fluidBlubsPerIn3);

    my $REs     = ($speeds*$segCGDiams)/$kinematicViscosityFluid;
    if (DEBUG and $verbose>=4){print "CHECK THIS: At least temporarily, am bounding RE's away from zero.\n"}
    my $minRE = 0.01;
    my $ok = $REs > $minRE;
    $REs = $ok*$REs + (1-$ok)*$minRE;
    
    my $CDrags  = $mult*$REs**$power + $min;
    my $FDrags  = $CDrags*(0.5*$fluidBlubsPerIn3*($speeds**2)*$segCGDiams*$segLens);
    # Unit length implicit.
    
    # Fix any nans that appeared:
    #$FDrags = ReplaceNonfiniteValues($FDrags,0);
    
    if ($verbose>=3){pq($type,$REs,$CDrags,$FDrags);print "\n"}
    
    return $FDrags;
}

### End New ======================


my ($VXs,$VYs,$VAs,$VNs,$FAs,$FNs,$FXs,$FYs);    # For reporting.


sub Calc_DragsCG { my $verbose = 0 ? $verbose : 0;
    my ($VXCGs,$VYCGs,$CGXs,$CGYs,$uXs,$uYs) = @_;
    
    ## Calculate the viscous drag force at each seg CG (and fly pseudo-seg CG) implied by the cartesian velocities there.
    
    # Water friction contributes drag forces to the line.  I use different normal and axial "moduli" to account for probably different form factors.  I would probably be more correct to use the real water friction coeff, and appropriately modelled form factors.  In any case, the drag coeffs should be proportional to section surface area.  Eventually I might want to acknowledge that the flows around the rod's hex section and the lines round section are different.
    
    # I use an arbitrary cartesian VCGs vector to compute the corresponding viscous deceleration vector.  I assume (quite reasonable given our typical numbers) that we remain enough below Reynolds numbers at which complex effects like the drag crisis come into play that the drag force is well enough modeled by a general quadratic function of the velocity (including the linear part, although this is probably unimportant).
    
    
    # Quite a bit of research has been done on the drag on an cylinder aligned obliquely to a uniform flow. Then, by the so called "independence" (Prandtl and otthers) for such flows, there are two different Reynolds number (RE) dependent drag coeffs, axial and normal, with the latter much larger than the former.  Each is computed from an RE based on the corresponding velocity component and applied to the signed squared velocity component and scaled by an appropriate area and air density to produce axial and normal drag forces.  These forces vector sum to produce the final drag force.  Under our assumptions, we get the usual aerodynamic behavior that at zero attack there is only axial drag, for small attack (normal, so "lift") force soon dominates.  With further increase in attack, lift/drag rises to a maximum, and then as attack approaches 90º, drops back to zero, with much larger total drag.
    
    # The 24 somehow comes from Stokes Law (http://www.aerospaceweb.org/question/aerodynamics/q0231.shtml), but Wolfram shows 7, while $minCDNormal ought to be about 1 (http://scienceworld.wolfram.com/physics/CylinderDrag.html):  see also  https://www.researchgate.net/publication/250693961_Drag_and_lift_coefficients_of_inclined_finite_circular_cylinders_at_moderate_Reynolds_numbers, https://www.academia.edu/31723559/Characterization_of_flow_contributions_to_drag_and_lift_of_a_circular_cylinder_using_a_volume_expression_of_the_fluid_force
    
    # https://deepblue.lib.umich.edu/bitstream/handle/2027.42/77547/AIAA-3583-939.pdf;sequence=1, which includes (p445, right column, 1st paragraph) "The investigation of three-dimensional boundary layers was greatly facilitated by  the independent observations of Prandtl (25),Sears (26) and Jones (27) that the equations of motion for incompressible viscous flow past a yawed cylinder are separable.  As a result, the components of the flow in the plane normal to the generators of the cylinder are independent of the angle of yaw — i.e.,  of the span wise velocity component.  This "independence principle" requires, however, that span wise derivatives of all flow properties be zero.  Therefore, transition to turbulence (see Section 3) as well as the development of the wake after laminar separation might be expected to be influenced by the yaw angle.
    
    # 25  Prandtl, L., Ueber Reibungsschichten bei Drei-Dimensionalen Stroemungen, pp. 134-141; Albert Betz Festschrift, Goettingen, Germany, 1945.  Available for money: https://link.springer.com/chapter/10.1007/978-3-662-11836-8_54?no-access=true
    
    # 26  Sears, W. R., The Boundary Layer on Yawed Cylinders, Journal of the Aeronautical Sciences, Vol. 15, No. 1, pp. 48-92, January, 1948. See also Boundary Layers in Three-Dimensional Flow (a  review), Applied Mechanics Reviews, Vol, 7, No. 7, pp. 281-285, 1954.
    
    # 27 Jones, R. T., Effects of Sweepback on Boundary Layers and Separation, NACA Rep. 884, 1947.  I have this article in the Hexrod Folder.  Source: http://naca.central.cranfield.ac.uk/reports/1947/naca-report-884.pdf
    
    # Cooke, J.C., The Boundary Layer of a Class of Infinite Yawed Cylinders", Proc. Cambr. Phil. Soc., Vol 46, p. 645, 1950.
    
    # http://dspace.mit.edu/bitstream/handle/1721.1/104715/14200305.pdf?sequence=1, see Introduction, discusses Sears.  1. Introduction.  A few cases have been solved for three-dimensional laminar boundaay layer.  Sears and Cooke (Refs. 1 and 2) have solved the boundary layer on yawed cylinders of infinite length. Since the main flow and the        boundary condition are uniform along the cylinder axis, the boundary layer is uniform along the axis too.  This         kind of flow was called "transferable across the main flow."  Consequently, the velocity component in the plane perpendicular to the axis is independent of the axial velocity component, although the boundary layer is three-dimensional.
    
    # http://wwwg.cam.ac.uk/web/library/enginfo/aerothermal_dvd_only/aero/fprops/introvisc/node11.html, abstract, but possibly interesting http://authors.library.caltech.edu/52564/, purchase http://fluidsengineering.asmedigitalcollection.asme.org/article.aspx?articleid=1433531
    
    # https://en.wikipedia.org/wiki/Strouhal_number
    
    # AXIAL FLOW DRAG
    
    # https://www.physicsforums.com/threads/drag-force-on-cylinder-in-parallel-flow.400516/  Lamb's Solution?? Stokes Paradox. https://en.wikipedia.org/wiki/Stokes%27_paradox (Creeping Flow, RE ~ 1.)  The paradox is caused by the limited validity of Stokes' approximation, as explained in Oseen's criticism: the validity of Stokes' equations relies on Reynolds number being small, and this condition cannot hold for arbitrarily large distances r.[8][2]  A correct solution for a cylinder was derived using Oseen's equations, and the same equations lead to an improved approximation of the drag force on a sphere.[9][10]
    
    # Drag Measurements on Long, Thin Cylinders at Small Angles and High Reynolds Numbers from www.dtic.mil/100.2/ADA426478.  I have this article in the Hexrod Folder.  See esp. eq (14), so CDragAxial is constant.  Relation of drag to momentum thickness of bdy layer??
    
    # http://adsabs.harvard.edu/abs/2004APS..DFD.EN001H, http://www.koreascience.or.kr/article/ArticleFullRecord.jsp?cn=DHJSCN_2012_v49n6_512 (abstract)
    
    # 3. K. M. CipoUa and W. L. Keith, "Momentum Thickness Measurements for Thick Axisymmetric Turbulent Boundary Layers", Journal of Fluids Engineering, vol. 125, 2003, pp. 569-575.  I have this article in the Hexrod Folder.
    
    # 4. K. M. CipoUa and W. L. Keith, "High Reynolds Number Thick Axisymmetric Turbulent Boundary Layer Measurements," Experiments in Fluids, vol. 35, no. 5, 2003, pp. 477-485.   I have this article in the Hexrod Folder.
    
    
    # Visualizations:  https://www.youtube.com/watch?v=hrX11VtXXsU    https://www.youtube.com/watch?v=8WtEuw0GLg0   https://www.youtube.com/watch?v=_zIbZgHjepY
    
    
    if (DEBUG and $verbose>=4){print "\nCalcDragsCG ----\n"}
    
    # Get the segment-centered relative velocities:
    #pq($VXCGs,$VYCGs);
    my $relVXCGs = -$VXCGs->copy;
    my $relVYCGs = -$VYCGs->copy;
    
    if ($airOnly){
        $isSubmergedMult = zeros($CGYs);
    }else{
        # Need modify only vx, since fluid vel is horizontal.
        my $fluidVXCGs;
        ($fluidVXCGs,$isSubmergedMult) =
            Calc_VelocityProfile($CGYs,$profileText,$bottomDepthFt,$adjustedSurfaceVelFtPerSec,$halfVelThicknessFt,$surfaceLayerThicknessIn);
        $relVXCGs += $fluidVXCGs;
        if ($verbose>=3){pq($fluidVXCGs)}
    }
    #pq($relVXCGs,$relVYCGs);
    
    # Deal with the ordinary segment and fly pseudo-segment separately:
    my $segRelVXCGs = $relVXCGs(0:-2);
    my $segRelVYCGs = $relVYCGs(0:-2);
    
    my $flyRelVX   = $relVXCGs(-1);
    my $flyRelVY   = $relVYCGs(-1);
    if ($verbose>=3){pq($segRelVXCGs,$segRelVYCGs)}
    
    # Project to find the axial and normal (rotated CCW from axial) relative velocity components at the segment cgs:
    $VAs =  $uXs*$segRelVXCGs + $uYs*$segRelVYCGs;
    $VNs = -$uYs*$segRelVXCGs + $uXs*$segRelVYCGs;
     if (DEBUG and $verbose>=4){pq($VAs,$VNs)}
    
    my $signAs = $VAs <=> 0;
    my $signNs = $VNs <=> 0;
    
    my $segIsSubmergedMult = $isSubmergedMult(0:-2);
    my $FAs = $signAs * Calc_SegDragForces(abs($VAs),$segIsSubmergedMult,"axial",$segCGDiams,$segLens);
    my $FNs = $signNs * Calc_SegDragForces(abs($VNs),$segIsSubmergedMult,"normal",$segCGDiams,$segLens);
    if (DEBUG and $verbose>=4){pq($FAs,$FNs)}

    my $FDragXCGs = $uXs*$FAs - $uYs*$FNs;
    my $FDragYCGs = $uXs*$FNs + $uYs*$FAs;
    
    # Compute axial and normal drags as if all the segments were taut.  Later I will modify these for the slack segements.  Of course, all the rod segments are taut.  Drag forces point opposite the velocities:
    if ($verbose>=3){pq($uXs,$uYs,$VAs,$VNs,$FAs,$FNs,$FDragXCGs,$FDragYCGs)}
    if (DEBUG and $verbose>=4){Calc_Kiting($VNs,$VAs,$FDragXCGs,$FDragYCGs)}

    
=for Enable me
    if ($nLineNodes and any(!$tautSegs)){
        # Adjust the slack segments as a strain-weighted combination of the taut drag and drag for a locally randomly oriented line.  These random drags point exactly opposite the original velocities, of course, independent from the nominal line seg orientation. (The "which" method works in peculiar ways around no slack segs.):
        
        my $tCoeffs = zeros($nThetas)->glue(0,-$lineStrains*(!$tautSegs));  # Between 1 at full and 0 at no slack.
        #pq($tautSegs,$lineStrains,$tCoeffs);
        
        # I can use the axial and normal Vs here too.
        my $tFRandNs    = -$segFluidMultRand*$VN2s;
        my $tFRandAs    = -$segFluidMultRand*$VA2s;
        
        $FNs = $tCoeffs*$tFRandNs + (1-$tCoeffs)*$FNs;
        $FAs = $tCoeffs*$tFRandAs + (1-$tCoeffs)*$FAs;
    }
=cut Enable me
    
    
    # Add the fly drag to the line. No notion of axial or normal here:
    $FDragXCGs = $FDragXCGs->glue(0,zeros(1));
    $FDragYCGs = $FDragYCGs->glue(0,zeros(1));
    
    # Add the fly drag to the line (or if none, to the rod) tip node. No notion of axial or normal here:
    my $flyIsSubmerged = $isSubmergedMult(-1);
    my $flySpeed = sqrt($flyRelVX**2 + $flyRelVY**2);
    if ($verbose>=3){pq($flyRelVX,$flyRelVY,$flySpeed)}
    
    my $flyMultiplier =
        Calc_SegDragForces($flySpeed,$flyIsSubmerged,"normal",$flyNomDiam,$flyNomLen);
    
    $FDragXCGs(-1)  += $flySpeed ? $flyMultiplier*$flyRelVX/$flySpeed : 0;
    $FDragYCGs(-1)  += $flySpeed ? $flyMultiplier*$flyRelVY/$flySpeed : 0;
    if ($verbose>=3){pq($FDragXCGs,$FDragYCGs)}
    
    my $FDragCGs = $FDragXCGs->glue(0,$FDragYCGs);
    if (DEBUG and $verbose>=4){pq ($FDragCGs)}

    return $FDragCGs;
}


sub Calc_Kiting {
    my ($VNs,$VAs,$FXs,$FYs) = @_;
    
    print "\n";
    
    # Compute off seg axis angles of the velocities:
    #pq($VNs,$VAs);
    
    my $relVelAngles = atan($VNs/$VAs)*180/$pi;
    pqf("%5.1f ",$relVelAngles);
    if (any($relVelAngles>90) or any($relVelAngles<-90)){die "Detected reversed velocity angle.";}
    
    # Compute the kiting effect as a check:
    #pq($FYs,$FXs);
    
    my $kitingAngles = atan($FYs/-$FXs)*180/$pi;
    pqf("%5.1f ",$kitingAngles);
    if (any($relVelAngles>90) or any($relVelAngles<-90)){die "Detected reversed velocity angle.";}
    
    print "\n";
}


my ($fluidDragsCGs,$pDotsFluidDragCG);  # For reporting

sub Calc_pDotsFluidDrag { my $verbose = 0?$verbose:0;
    #    my ($qs,$qDots,$driverX,$driverY,$driverTheta) = @_;
    
    ## Cartesian forces applied at the nodes, either directly, or by generating torques, change the conjugate momenta.  In principle, this function could be combined with Calc_pDotsGravity, to avoid a separate matrix multiplication, but that doesn't allow my special handling of friction effects that I seem to need to keep the solver happy.
    
    
    if (DEBUG and $verbose>=4){print "\nCalc_pDotsFluidDrag ----\n"}
    
    my ($CGXs,$CGYs) = Calc_CGQs();
    
    my $VXCGs = $CGQDots(0:$nCGs-1);
    my $VYCGs = $CGQDots($nCGs:-1);
    
    
    $fluidDragsCGs = Calc_DragsCG($VXCGs,$VYCGs,$CGXs,$CGYs,$uXs,$uYs);
    #$fluidDragsCGs = Calc_FluidDragsCG($CGQDots);
    if ($verbose>=3){print " fluidDragsCGs = $fluidDragsCGs\n"}
    
    $pDotsFluidDragCG = ($fluidDragsCGs x $dCGQs_dqs)->flat;
    if ($verbose>=3){print " pDotsFluidDragCG = $pDotsFluidDragCG\n"}
    # Sign was already set in Calc_FluidDragsCG to oppose the velocities.
    
    return $pDotsFluidDragCG;
}


#my $frictionAdjustFract = 0.1;
my $frictionAdjustFract = 1000000000;
my $frictionRatios = pdl(0); # 1 means no adjustment.


my ($pDots_NonVsFrict,$rodStaticError);   # For reporting.

sub Calc_pDots { my $verbose = 1?$verbose:0;
    my ($t) = @_;   # $t is a PERL scalar.
    
    ## Compute the change in the conjugate momenta due to the internal and cartesian forces.
    
    # To try to avoid sign errors, my convention for this function is that all contributions to $pDots are plus-equaled.  It is the job of each contributing calculator to get its own sign right.
    
    # 9/20/17 - To try to help the solver, rearranged this function so that frictional forces will never reverse the sign accelerations due to the non-frictional forces.  In fact, what I really would want is to not change the sign of any of the nodal velocities.  Even with high damping moduli, a sufficient shortening of the integration timestep will always give valid behavior, but the cost to total integration time (and perhaps machine accuracy) becomes prohibitive.

    if (DEBUG and $verbose>=4){print "\nCalc_pDots ----\n"}

    $pDots  .= 0;
    
    #    if (!$programmerParams{zeroPDotsKE} and $nRodNodes>0){
    if (!$programmerParamsPtr->{zeroPDotsKE} and $nThetas){
        my $pDotsKE = Calc_pDotsKE();
        if (DEBUG and $verbose>=4){pq $pDotsKE}
        
        # Be careful to put the result in the right place.  See comments in Calc_pDotsKE().
        $pDots(0:$nThetas-1) += $pDotsKE;
        if (DEBUG and $verbose>=4){print " After KE: pDots=$pDots\n";}
    }

    # Compute the acceleration due to the potential energy.  First, from the rod thetas:
    
    # First, deal with the rod nodes bending energy and internal friction:
    my $pThetaDotsK;
    if ($nThetas){
        
        if (DEBUG and $verbose>=5){pq $dthetas}

        #        if (!$programmerParams{zeroPThetaDots}){
        if (!$programmerParamsPtr->{zeroPThetaDots}){

            ## This handles the angle alignment constraint force from the driver motion, but not the cartesian force on the handle base.  That force is applied in Calc_pDotsConstraints.
            
            $pThetaDotsK = -$rodKsNoTip*$dthetas;
            # NOTE:  The tip node DOES NOT contribute to the bending energy since the line connects to the rod there, and there is no elasticity at that hinge point.  However, the handle node DOES contribute.  Positive theta should yield a negative contribution (??) to thetaDot.  Aside from the constants, we are taking the theta derivative of (theta/segLen)^2, so 2*theta/(segLen^2), and I have absorbed all the constants into multiplier. ??  ???
            if (DEBUG and $verbose>=4){pq $pThetaDotsK}
            $pDots(0:$nThetas-1) += $pThetaDotsK;
            
            if (DEBUG and $verbose>=4){print " After thetas: pDots=$pDots\n";}
        }
    }       
    
    my ($pDotsLineK,$pDotsLineC,$lineTensionAtRodTip);
    
    #    if ($nLineNodes and !$programmerParams{freeLineNodes}){
    if ($nLineNodes and !$programmerParamsPtr->{freeLineNodes}){
        ($pDotsLineK,$pDotsLineC,$lineTensionAtRodTip) = Calc_pDotsLine();
        if (DEBUG and $verbose>=4){pq($pDotsLineK,$pDotsLineC)}

        $pDots($idx0:-1) += $pDotsLineK;
        if (DEBUG and $verbose>=4){print " After Line: pDots=$pDots\n";}
    }

    
    # I need to do fluid drag and gravity separately
    if ($g){
        #        my $pdcfs = Calc_pDotsCartForces();
        my $pDotsGravity = Calc_pDotsGravity();
        $pDots += $pDotsGravity;
        if (DEBUG and $verbose>=4){print " After cart forces: pDots=$pDots\n";}
        
        if ($nThetas){$rodStaticError = $pThetaDotsK + $pDotsGravity(0:$nThetas-1)}
        # In equilibrium, these cancel.
    }
    
    
    my $tFract = SmoothChar(pdl($t),$tipReleaseStartTime,$tipReleaseEndTime);
        # Returns 1 if < start time, and 0 if > end time.
    if ($holding == 1 and $tFract == 1){    # HOLDING
        
        $pDots($idy0-1) .= 0;   # Overwrite any tip adjustments that other Calcs might have provided.
        $pDots(-1)      .= 0;
        
        my $pDotsTip_HOLD = Calc_pDotsTip_HOLD($t,$tFract);
        $pDots += $pDotsTip_HOLD;
        if (DEBUG and $verbose>=4){pq $pDotsTip_HOLD}
        if (DEBUG and $verbose>=4){print " After tip hold: pDots=$pDots\n";}
        
    } elsif ($holding == -1 and $tFract>0 and $tFract<1){   # RELEASING

        my $pDotsTip_SOFT_RELEASE = Calc_pDotsTip_SOFT_RELEASE($t,$tFract);
        $pDots += $pDotsTip_SOFT_RELEASE;
        if (DEBUG and $verbose>=4){pq $pDotsTip_SOFT_RELEASE}
        if (DEBUG and $verbose>=4){print " After tip soft release: pDots=$pDots\n";}
    }
    

    # Deal with the frictional forces:
    my $pDotsFriction = zeros($nqs);
    if ($nThetas){
        $pDotsFriction(0:$nThetas-1)    .= -$rodCsNoTip*$dthetaDots;
    }
    
    if ($nLineNodes) {
        $pDotsFriction($idx0:-1)    .= $pDotsLineC;
    }
    
    if ($calculateFluidDrag){
        $pDotsFriction += Calc_pDotsFluidDrag();    # Sets $isSubmergedMult
    } else {
        $isSubmergedMult = zeros($pDots);
    }

    
    if (!$nThetas and !$airOnly and any($isSubmergedMult)){  # Need to do this at each step since only some of the cgs may be underwater at any given time.
        
        #pq($CGBuoys,$isSubmergedMult);
        
        if ($gravity) {

            my $FBuoyYs = $g*$CGBuoys*$isSubmergedMult;
            if (DEBUG and $verbose>=4){pq($FBuoyYs)}
            
            my $line_pDotsBuoyancy = ($FBuoyYs x $lineLowerTriPlus)->flat;
            # Negative, positive g force always points down.
            if (DEBUG and $verbose>=4){pq $line_pDotsBuoyancy}
            
            #pq($line_pDotsBuoyancy,$isSubmergedMult,$pDots);

            $pDots($idy0:-1) += $line_pDotsBuoyancy;
            # affects only y coords.
            #pq($pDots);
        }
    }
    
    # Try to help the solver by making sure that friction cannot change the sign of a dynamical momentum:
    #    $pDotsFriction = Adjust_pDots_Friction($h,$ps,$pDotsFriction);
    
    if ($isRK0){$pDots_NonVsFrict = $pDots->glue(1,$pDotsFriction);}

    $pDots += $pDotsFriction;

	if (DEBUG and $verbose>=4){ pq $pDots}
    return $pDots;
}




sub Set_SLOW_START_SurfVel { my $verbose = 1?$verbose:0;
    my ($t) = @_;   # $t is a PERL scalar.
    
     my $tFract = ($surfAccelDuration) ?
            1-SmoothChar(pdl($t),$surfAccelStartTime,$surfAccelEndTime) : 1;
    pq($tFract,$surfaceVelFtPerSec);
    $adjustedSurfaceVelFtPerSec = $tFract*$surfaceVelFtPerSec;
    if ($verbose>=3){pq($adjustedSurfaceVelFtPerSec)}

    return $adjustedSurfaceVelFtPerSec;
}


sub Set_SLOW_START_Gravity { my $verbose = 1?$verbose:0;
    my ($t) = @_;   # $t is a PERL scalar.


    my $tFract = ($gravAccelDuration >= 0) ?
        1-SmoothChar(pdl($t),$gravAccelStartTime,$gravAccelEndTime) : 1;
    #pq($tFract,$gravity);
    $g = $tFract*$gravity;
    if ($verbose>=3){pq($g)}
    
    return $g;
}


sub Set_HeldTip { my $verbose = 1?$verbose:0;
    my ($t) = @_;   # $t is a PERL scalar.
    
    # During hold, the ($dxs(-1),$dys(-1)) are not treated as dynamical variables.  Instead, they are made into quantities dependent on all the remaining dynamical varibles and the fixed fly position ($XTip0,$YTip0).  This takes the fly's mass and drag out of the calculation, but the mass of the last line segment before the fly still acts at that segment's cg and its drag relative to its spatial orientation, due to changes in the cg location caused by the motion of the last remaining node ($Xs(-2),$Ys(-2)).
    
    if (!$nLineNodes){die "Hold not allowed if there are no line nodes."}
 
    Calc_Driver($t);
    Calc_dQs();
    
    $XTip0 = $driverX+sumover($dXs);
    $YTip0 = $driverY+sumover($dYs);
    if (DEBUG and $verbose >=4){print "\nSet_HOLD:\n";pq($XTip0,$YTip0,$qs,$ps);print "\n";}
}


sub Get_HeldTip {
    return ($XTip0,$YTip0);
}


my $stripCutoff = 0.0001;    # Inches.

sub AdjustFirstSeg_STRIPPING { my $verbose = 0?$verbose:0;
    my ($t) = @_;

    #pq($segLens,$lineSegNomLens,$segWts,$CGWts,$CGQMasses,$line_pDotsStdGravity,$CGBuoys);

    my $stripNomLen = $lineSegNomLensFixed(0) - ($t-$thisSegStartT)*$stripRate;
    #if ($stripNomLen < $stripCutoff){$stripNomLen = $stripCutoff}
    if ($stripNomLen < $stripCutoff){return}  # Don't make any more changes in this seg.
    if ($verbose>=3){pq($stripNomLen)}
   
    #if ($stripNomLen < $stripCutoff){return 0}
    
    $segLens($idx0)         .= $stripNomLen;
    $lineSegNomLens(0)      .= $stripNomLen;
    
    my $prevFirstSegWt  = $segWts($idx0)->copy;    # For correction to $line_pDotsStdGravity
    my $stripWt         = $lineSegWtsFixed(0) * ($stripNomLen/$lineSegNomLensFixed(0));
    $segWts($idx0)           .= $stripWt;
        # At least approximately right.
    $CGWts($idx0)            .= $stripWt;
    $CGQMasses($idx0)        .= $massFactor*$stripWt;
    $CGQMasses($idx0+$nCGs)  .= $massFactor*$stripWt;

    # Correction due to first seg is only in the first entry.
    my $currFirstSegWt  = $segWts($idx0)->copy;
    $line_pDotsStdGravity(0)    -= $currFirstSegWt - $prevFirstSegWt;   # sic -=, due to the minus in $line_pDotsStdGravity.
    
    #$segCGDiams($idx0)      .= ??      For the moment, leave this unchanged.
    my $tDiam   = $segCGDiams($idx0);
    my $tLen    = $stripNomLen;
    my $tVol    = ($pi/4) * $tDiam**2 * $tLen;
    $CGBuoys($idx0)     .= $tVol*$waterOzPerIn3;
    
    # For now, will leave cg unchanged.
    if ($verbose>=3){pq($stripNomLen,$stripWt)}
    #pq($segLens,$lineSegNomLens,$segWts,$CGWts,$CGQMasses,$line_pDotsStdGravity,$CGBuoys);
    
}


sub AdjustTrack_STRIPPING { my $verbose = 1?$verbose:0;
    my ($t) = @_;
    
    ### Doesn't seem to be necessary since $stripCutoff = 0.0001;    # Inches. works in preliminary tests.  Cutoff = 0, however, blows up, as expected.
}

sub Set_ps_From_qDots { my $verbose = 1?$verbose:0;
	my ($t) = @_;
    
    ## !!! I'm not certain I trust this, but it is based on taking the qDot partials of KE.

    ## The conjugate momenta ps are defined in as the as the partial derivatives of the kinetic energy with respect to thetaDots (DVMat).  This function returns them as a flat matrix.  It is only explicitly used in setting the initial conditions for the ODE solver.  During integration, Calc_qDots() turns things around, delivering the qDots from the ps.

    # We evaluate the matrix equation
    #       ps = Dtrans*M*V = Dtrans*M*(Vext+D*thetaDots).
    # where D is the DVMat calculated above, Dtrans is its transpose, M is the expanded diagonal matrix of node masses corresponding the x and y components of the cartesian positions, and V is the column vector of cartesian velocities.

    # This inverts to
    #       thetaDots = ((Dtrans*M*D)inv)*(P-Dtrans*M*Vext).


    ### If we wanted to start with the line moving to the right at some velocity, could just turn that on as a forcing in this function (or do you need to keep it on for a while.  A bit like attaching a rocket motor to the rod tip to produce an impulse.

    PrintSeparator("Initialize ps",3);

    # Requires that $qs, $qDots have been set:
    Calc_Driver($t);
    if ($nThetas){Calc_CartesianPartials()};    # Else done once during initialization.
    Calc_ExtCGVs();
    Calc_CGQDots();

#pq($CGQMasses,$CGQDots);
    my $Ps = $CGQMasses*$CGQDots;
#pq $Ps;
    
    #??? is this true???  I don't think so. $ps are the conjugate momenta computed by d/dqDots of the KE.
    #But maybe it comes to the same thing.'
    $ps .= ($Ps x $dCGQs_dqs)->flat;
    #    my $test = ($dCGQs_dqs->transpose x $Ps->transpose)->flat;
    #    pq($ps,$test);

    if ($verbose>=3){pq $ps}
    #    return $ps;
}


sub DE_GetStatus {
    return $DE_status;
}

my ($DE_numCalls,$DEfunc_numCalls,$DEjac_numCalls,$DEfunc_dotCount,$DE_reportStep);
my $DEdotsDivisor = 100;

sub DE_InitCounts {

    $DE_numCalls        = 0;
    $DEfunc_numCalls    = 0;
    $DEjac_numCalls     = 0;
    $DEfunc_dotCount    = 0;
    $DE_reportStep      = 1;
}

sub DE_GetCounts {
    
    return ($DE_numCalls,$DEfunc_numCalls,$DEjac_numCalls,$DEfunc_dotCount);
}


# Integration outputs:
#my ($maxHandleQDiff,$maxHandleThetaDiff,
my ($maxTipDiff);
my ($maxLineStrains,$maxLineVs);
my ($plotLineVXs,$plotLineVYs,$plotLineVAs,$plotLineVNs,$plotLine_rDots);

sub DE_InitExtraOutputs { my $verbose = 0?$verbose:0;
    
    $maxTipDiff         = zeros(1)->flat;
    
    $maxLineStrains = zeros($numLineNodes);
    $maxLineVs      = zeros($numLineNodes);
    
    $plotLineVXs    = zeros(0);
    $plotLineVYs    = zeros(0);
    $plotLineVAs    = zeros(0);
    $plotLineVNs    = zeros(0);
    $plotLine_rDots = zeros(0);
}

sub Get_ExtraOutputs {
    return ($plotLineVXs,$plotLineVYs.$plotLineVAs,$plotLineVNs,$plotLine_rDots);
}


sub DE_ReportStep {  my $verbose = 1?$verbose:0;
    my ($t,$dynams,$h,$dynamDots) = @_;
    
    ## At the end of the RK0 call after a successful integration step, take the chance to report and accumulate.
    
    # For RHexPlotExtras()  ----------------
 
    my $tt = pdl($t);
    
    if ($nLineNodes) {
        
        Calc_QDots();
        
        # Stretching velocities:
        my $tLine_rDots = $tt->glue(0,$rDotsLine);
        $plotLine_rDots = $plotLine_rDots->glue(1,$tLine_rDots);
    #pq $plotLine_rDots;
        
        my $tLineVXs = $QDots($nThetas:$nINodes-1);
        my $tLineVYs = $QDots($nINodes+$nThetas:-1);
        my $lineVs = sqrt($tLineVXs**2 +$tLineVYs**2);

        
        $tLineVXs = $tt->glue(0,$tLineVXs);
        $tLineVYs = $tt->glue(0,$tLineVYs);
    #pq($tLineVXs,$tLineVYs);
        $plotLineVXs = $plotLineVXs->glue(1,$tLineVXs);
        $plotLineVYs = $plotLineVYs->glue(1,$tLineVYs);

        if ($calculateFluidDrag){
            my $tLineVNs = $tt->glue(0,$VNs);
            my $tLineVAs = $tt->glue(0,$VAs);
    #pq($tLineVAs,$tLineVNs);
            $plotLineVNs = $plotLineVNs->glue(1,$tLineVNs);
            $plotLineVAs = $plotLineVAs->glue(1,$tLineVAs);
        }

        # Keep a record of the max line strains and Vs:
        my $tMask = $lineStrains>=$maxLineStrains;
        $maxLineStrains = $tMask*$lineStrains+(!$tMask)*$maxLineStrains;

        $tMask = $lineVs>=$maxLineVs;
        $maxLineVs = $tMask*$lineVs+(!$tMask)*$maxLineVs;
    }

    # Run-time printing  -------------------
    
    if ($verbose>=1){
        if ($verbose>=2){
            printf("\nSTEP OK (t=%.10f, frame=%.2f, fcalls=%d, jcalls=%d)\n",$t,$t*$frameRate,$DEfunc_numCalls,$DEjac_numCalls);
        }
        
        if (DEBUG and $verbose>=4){
            pq($dynams,$dynamDots);
        }
        
        if (DEBUG and $verbose>=4){
            printf(" (hX,hY,hTheta)=(%.6f,%.6f,%.6f)",$driverX,$driverY,$driverTheta);
            printf(" (hXDot,hYDot,hThetaDot)=(%.6f,%.6f,%.6f)",$driverXDot,$driverYDot,$driverThetaDot);
        }
        
        if ($verbose>=3){
            if ($t <= $tipReleaseStartTime){
                printf(" HOLDING: (len,strain,taut)=(%.6f,%.6f,%d)\n",
                    sclr($RDiffHeld),sclr($strainHeld),sclr($tautHeld));
                
                my ($Xs,$Ys) = Calc_Qs($t,$dynams(0:$nqs),0);
                printf("    TIP: (X,Y)=(%.6f,%.6f)\n",sclr($Xs(-1)),sclr($Ys(-1)));
                printf("    SEG: (dX,dY)=(%.6f,%.6f)\n",sclr($dxs(-1)),sclr($dys(-1)));

            } elsif ($t <= $tipReleaseEndTime){
                printf(" SOFT RELEASE: (stretch,k)=(%.6f,%.6f)\n",
                sclr($RDiffSoft),sclr($tKSoft));
                
                my ($Xs,$Ys) = Calc_Qs($t,$dynams(0:$nqs),0);
                printf("    TIP: (X,Y)=(%.6f,%.6f)\n",sclr($Xs(-1)),sclr($Ys(-1)));
                printf("    FIX: (X,Y)=(%.6f,%.6f)\n",sclr($XTip0),sclr($YTip0));
            }
        }
        
        if ($verbose and any(abs($dthetaDots) > 100/$nRodNodes)){
            print "WARNING: Detected suspiciously high values: ";pqf("%.3f ",$dthetas,$dthetaDots);
        }
        
        if ($verbose and any($frictionRatios > 0.5)){
            print "WARNING: Detected suspiciously high values: ";pqf("%.1f ",$frictionRatios);
        }

=for comment
        if ($verbose>=3){
            my $pDotsFrictOverNon = $pDots_NonVsFrict(:,1)/$pDots_NonVsFrict(:,0);
            #           pq($pDots_NonVsFrict);
            print " pDots Friction/NonFriction - \n";
            my $rod = $pDotsFrictOverNon(0:$nThetas-1);
            print " "; pqf("%8.0e ",$rod);
            pqf("%.5f",$frictionRatios);

            if ($nLineNodes){
                my $lineX = $pDotsFrictOverNon($idx0:$idy0-1);
                print " "; pqf("%8.0e ",$lineX);
                my $lineY = $pDotsFrictOverNon($idy0:-1);
                print " "; pqf("%8.0e ",$lineY);
            }
        }
=cut
        
        #        my $ttt = sprintf("%.4f",$t);
        my $ss;
        my $frame = sprintf("%.2f",$t*$frameRate);
        if ($nLineNodes){

            print "frame=$frame - root $tautSegs tip$vs";

            if ($verbose>=3){
                $ss=""; foreach my $ff ($lineStrains->list){
                $ss .= sprintf("%.4f ",$ff);
                }
                print " lineStrains: $ss\n";
            }
            if (DEBUG and $verbose>=4){
                print "\tlineStrains    = $lineStrains\n";
                print "\tmaxLineStrains = $maxLineStrains\n";
                print "\n";
            }
        } else {print "frame=$frame$vs"}
        
        if (DEBUG and $nLineNodes and $calculateFluidDrag and $verbose>=4){
            my $CGXDots = $CGQDots(0:$nCGs-1);
            my $CGYDots = $CGQDots($nCGs:-1);
            
            pq($CGXDots,$CGYDots,$fluidDragsCGs,$pDotsFluidDragCG);
        }

        
        if ($verbose>=3 and $nRodNodes>1 and !$nLineNodes and $g){
            # We are likely replicating RHexStatic, so show static error.
            print " ";pqf("%.2e ",$rodStaticError);
        }
        
        if (DEBUG and $verbose>=4 and $nRodNodes>1 and $calculateFluidDrag){
            print " Rod:\n";

            if (DEBUG and $verbose>=4){
                my @XVals = $uXs(0:$nThetas-1)->list;
                my @YVals = $uYs(0:$nThetas-1)->list;
                $ss="";for (my $ii=0;$ii<$nRodNodes-1;$ii++){
                    $ss .= sprintf("(%6.2f,%6.2f) ",$XVals[$ii],$YVals[$ii]);
                }
                print "  (uX,uY): $ss\n";
                
                @XVals = $VXs(0:$nThetas-1)->list;
                @YVals = $VYs(0:$nThetas-1)->list;
                $ss="";for (my $ii=0;$ii<$nRodNodes-1;$ii++){
                    $ss .= sprintf("(%6d,%6d) ",$XVals[$ii],$YVals[$ii]);
                }
                print "  (VX,VY): $ss\n";
                
                my @AVals = $VAs(0:$nThetas-1)->list;
                my @NVals = $VNs(0:$nThetas-1)->list;
                $ss="";for (my $ii=0;$ii<$nRodNodes-1;$ii++){
                    $ss .= sprintf("(%6d,%6d) ",$AVals[$ii],$NVals[$ii]);
                }
                print "  (VA,VN): $ss\n";

                @AVals = $FAs(0:$nThetas-1)->list;
                @NVals = $FNs(0:$nThetas-1)->list;
                $ss="";for (my $ii=0;$ii<$nRodNodes-1;$ii++){
                    $ss .= sprintf("(%6.0e,%6.0e) ",$AVals[$ii],$NVals[$ii]);
                }
                print "  (FA,FN): $ss\n";

                @XVals = $FXs(0:$nThetas-1)->list;
                @YVals = $FYs(0:$nThetas-1)->list;
                $ss="";for (my $ii=0;$ii<$nRodNodes-1;$ii++){
                    $ss .= sprintf("(%6.0e,%6.0e) ",$XVals[$ii],$YVals[$ii]);
                }
                print "  (FX,FY): $ss\n";
            }

 # Compute the kiting effect as a check:
            my $vxs = $VXs(0:$nThetas-1);
            my $vys = $VYs(0:$nThetas-1);
            my $vlens = sqrt($vxs**2 + $vys**2);
            $vxs /= $vlens;
            $vys /= $vlens;
            
            my $fxs = $FXs(0:$nThetas-1);
            my $fys = $FYs(0:$nThetas-1);
            $vlens = sqrt($fxs**2 + $fys**2);
            $fxs /= $vlens;
            $fys /= $vlens;
            
            my $kitingAngles = acos($vxs*$fxs+$vys*$fys)*180/$pi;
            
            my @KVals = $kitingAngles->list;
            $ss="";for (my $ii=0;$ii<$nRodNodes-1;$ii++){
                $ss .= sprintf("(%5.1f) ",$KVals[$ii]);
            }
            print "  (Kiteº): $ss\n";

            if (any($kitingAngles<90) or any($kitingAngles>270)){die "Detected reversed kiting angle.";}
        }
        if ($verbose>=3){print "\n"}
    }
}


my $prevT=0;

sub DE { my $verbose = 1?$verbose:0;    # Do a single DE step.
    my ($t,$Dynams,$caller)= @_;     # $Dynams is a 1d pdl, the rest are PERL scalars.
    
    ## Express the differential equation of the form required by RungeKutta.  The y vector flat (or a row vector).
    my $nargin = @_;
    if ($nargin<2){die "The first two args must be passed.\n"}
    if ($nargin<3){$caller = ""}
    
    if ($caller eq "DEjac_GSL" and $verbose<4){$verbose = 0}
    
    $DE_numCalls++;
    if ($verbose>=3){print "\nEntering DE (t=$t,caller=$caller),call=$DE_numCalls ...\n"}

    #pq($t);
    $tDynam = $t;
    $dynams .= $Dynams->flat;
        # $Dynams here is a variable maintained by the solver.  $dynams is my global, in terms of which the computation variables are defined.  THUS, I can freely vary $dynams for my purposes, but that doesn't affect the solver's copy.
    if ($verbose>=3){
        #pq($dynams);
        #pqInfo($dynams);
        my $DE_qs = $dynams(0:$nqs-1);
        pq($DE_qs);
        #my $DE_ps = $dynams($nqs:-1);
        #pq($DE_ps);
    }

    if (DEBUG and $verbose>=4){
        my $dt = $t-$prevT;
        if ($dt){pq($dt)}
        $prevT = $t;
    }
    
    if ($surfAccelDuration){Set_SLOW_START_SurfVel($t)}
    if ($gravAccelDuration){Set_SLOW_START_Gravity($t)}
    
    if (DEBUG and $verbose>=4){pq($Dynams)}
    
    my $status      = 0;
    my $dynamDots   = zeros($dynams);
    
    
    $isRK0 = 0;

   # Run control from caller:
    #    &{$RHexCastRunControl{callerUpdate}}();
    #    if ($RHexCastRunControl{callerRunState} != 1) {
    &{$runControlPtr->{callerUpdate}}();
    if ($runControlPtr->{callerRunState} != 1) {
    
        $DE_ErrMsg = "Caller interrupt";
        if ($verbose>=3){print "$DE_ErrMsg$vs"}
        $status = -1;
        return ($status,$dynamDots);
    }
    
    # Report the initial h of each cycle:
    #if ($jRK == 0){ $dT = $h}
    

    if (DEBUG and $verbose>=5){pq $dynams}
    
    if (DEBUG and $verbose>=4){pq($qs,$ps)};
    
    if ($stripping){
        AdjustFirstSeg_STRIPPING($t);
    }

    # Set global coords and external velocities.  See Set_ps_From_qDots():
    Calc_Driver($t);
#print "A\n";
        # This constraint drives the whole cast. Updates the driver globals.
        
#print "DE($t): hx=$driverX, hy=$driverY, htheta=$driverTheta\n hxd=$driverXDot, hyd=$driverYDot, hthetad=$driverThetaDot\n";
    
    Calc_dQs();
    if ($verbose>=3){pq($lineStrains)}
#    print "B\n";
        # Could compute $Qs now, but don't need them for what we do here.
    
    if ($nThetas){Calc_CartesianPartials()};    # Else done once during initialization.
#    print "C\n";
        # Updates $dCGQs_dqs, $d2CGQs_d2thetas and $dCGQs_dqs.
        
    Calc_ExtCGVs();
    if (DEBUG and $verbose>=4){pq($extCGVs);print "D\n";}
       # The contribution to QDots from the driving motion only.  This needs only $dQs_dqs.  It is critical that we DO NOT need the internal contributions to QDots here.
    
    Calc_qDots();
    if (DEBUG and $verbose>=4){pq($qDots);print "E\n";}
        # At this point we can find the NEW qDots.  From them we can calculate the new INTERNAL contributions to the cartesian velocities, $intVs.  These, always in combination with $extCGVs, making $Qdots are then used for then finding the contributions to the NEW pDots due to both KE and friction, done in Calc_pDots() called below.
    
    #pq $dQs_dqs;
    Calc_CGQDots();
    if (DEBUG and $verbose>=4){pq($CGQDots);print "F\n";}
    # Finds the new internal cartesian velocities and adds them to $extCGVs computed above.

    Calc_pDots($t);
    if (DEBUG and $verbose>=4){pq($pDots);print "G\n";}

    if ($nLineNodes){
        #        if ($programmerParams{detachLastLineNode}) {
        if ($programmerParamsPtr->{detachLastLineNode}) {
            $pDots(-$nLineNodes-1)  .= 0;
            $pDots(-1)              .= 0;
            if ($verbose>=2){print "Detaching:\n"};
        }
        if (DEBUG and $verbose>=4){pq($qDots,$pDots)};
    }
    #print "\n\nExiting DE\n"; pq($qDots,$pDots); print "\n\n";

    #print "***   ";    pq($qDots);
    
    $dynamDots(0:$nqs-1)        .= $qDots;
    $dynamDots($nqs:2*$nqs-1)   .= $pDots;

    
    #print "Exiting DE  t=$t\n\n";
    #    pq($dynams,$dynamDots);
    #    pq($x0,$y0,$driverX,$driverY);
    #print "\n\n";
    
    if (DEBUG and $verbose>=5){print "\tdynamDots=$dynamDots\n"}
    if (DEBUG and $verbose>=4){print "... Exiting\n"}
    if (DEBUG and $verbose>=4){pq($dynamDots);print"\n"}
    
    if ($verbose>=2 and $t >= $T0+$DE_reportStep*$dT){
        #DE_ReportStep($t,$dynams,$dynamDots);
        printf("\nt=%.3f   ",$tDynam);
        $DE_reportStep++;
    }
    
    return ($status,$dynamDots);   # Keep in mind that this return is a global, and you may want to make a copy when you make use of it.
}                                                                            


my @aDynams0Block;   # Returned by initialization call to DEfunc_GSL


sub DEset_Dynams0Block {
    my (@a) = @_;
    
    @aDynams0Block = @a;
    if ($verbose>=3){pq(\@aDynams0Block)}

}



sub DEfunc_GSL { my $verbose = 1?$verbose:0;
    my ($t,@aDynams) = @_;
    
    ## Wrapper for DE to adapt it for calls by the GSL ODE solvers.  These do not pass along any params beside the time and dependent variable values, and they are given as a perl scalar and perl array.  Also, the first call is made with no params, and requires the initial dependent variable values as the return.
    
    unless (@_) {if ($verbose>=3){print "Initializing DEfunc_GSL\n"; pq(\@aDynams0Block)}; return @aDynams0Block}
    #unless (@_) {return @aDynams0Block}

    if ($verbose>=2 and $DEfunc_dotCount % $DEdotsDivisor == 0){print "."}
    $DEfunc_dotCount++;     # starts new after each dash.
    $DEfunc_numCalls++;
    
    #pq($tTry);


    my $dynams = pdl(@aDynams);
    if (DEBUG and $verbose>=4){pq($t,$dynams)}
    
    my ($status,$dynamDots) = DE($t,$dynams,"DEfunc_GSL");
    if (DEBUG and $verbose>=4){pq($status,$dynamDots)}
    
    my @aDynamDots = $dynamDots->list;

    # AS DOCUMENTED in PerlGSL::DiffEq: If any returned ELEMENT is non-numeric (eg, is a string), the solver will stop solving and return all previously computed values.  NOTE that they seem really to mean what they say.  If you set the whole return value to a string, you (frequently) get a segmentation fault, from which the widget can't recover.
    if ($status){$DE_status = $status; $aDynamDots[0] = "stop"}
    
    return @aDynamDots;   # Effectively copies.
}


sub DEjacHelper_GSL { my $verbose = 0?$verbose:0;
    my ($timeGlueDynams) = @_;  # arg is pdl vect $dynams, no explicit time dependence
    
    if (!defined($timeGlueDynams)){print "XX\n"; die; return pdl(0)->glue(0,pdl(DEfunc_GSL()))}
    # This is never called.
    
    #pq($$timeGlueDynams);
    my $t       = $timeGlueDynams(0)->sclr;
    my $dynams  = $timeGlueDynams(1:-1);
    
    if ($verbose>=3){pq($t,$dynams)}
    my ($status,$dynamDots) = DE($t,$dynams,"DEjac_GSL");
    if ($verbose>=3){pq($dynamDots)}
    
    return $dynamDots;  # No first time element after init?
    #    return $dynamDots->copy;
}


my ($JACfac,$JACythresh,$JACytyp);

sub JACInit { my $verbose = 1?$verbose:0;
    
    PrintSeparator("Initialize JAC",3);
    
    $JACfac             = zeros(0);
    #my $ynum0           = DEjacHelper_GSL();
    my $ynum0           = 1 + 2*$nqs;
    $JACythresh         = 1e-8 * ones($ynum0);
    $JACytyp            = zeros($JACythresh);
    if ($verbose>=3){pq($JACythresh,$JACytyp,$ynum0)}
}


sub JAC_FacInit {
    my ($restartJACfac) = @_;

    PrintSeparator("Initialize JACfac (but help me)",3);
    
=for
    if (defined($restartJACfac)){
        PrintSeparator("Initialize JACfac (restarting)",3);
        $JACfac = $restartJACfac;
        pq($JACfac);

    }else {
        PrintSeparator("Initialize JACfac",3);
        $JACfac = zeros(0);
    }
=cut
}

sub JAC_OtherInits {
    
    #my $ynum0           = DEjacHelper_GSL();
    my $ynum0           = 1 + 2*$nqs;
    $JACythresh         = 1e-8 * ones($ynum0);
    $JACytyp            = zeros($JACythresh);
    if ($verbose>=3){pq($JACythresh,$JACytyp,$ynum0)}
}

sub JACget {
    return ($JACfac,$JACythresh,$JACytyp);
}

sub DEjac_GSL { my $verbose = 1?$verbose:0;
    my ($t,@aDynams) = @_;
    
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
    
    if (DEBUG and $verbose>=4){print "\n\nEntering DEjac_GSL (t=$t)\n"}
    if (DEBUG and $verbose>=4){pq(\@aDynams)}
    
    ### NOTE:  The ODE SOLVER does not give back the last good step.  I am going to take the args passed here to be good if the time gets larger.
    
    $DEjac_numCalls++;
    $DEfunc_dotCount = 0;
    if ($verbose>=2){print "-"}
    
    my $timeGlueDynams    = pdl($t)->glue(0,pdl(@aDynams));
    #pq($timeGlueDynams);
    # In my scheme, funcnum takes the single pdl vector arg $y, with $tTry as its first element.
    my $dynamDots      = DEjacHelper_GSL($timeGlueDynams);
    #pq($dynamDots);
    #pq($JACythresh,$JACytyp,$JACfac);
    
    my ($dfdy,$nfcalls) = numjac(\&DEjacHelper_GSL,$timeGlueDynams,$dynamDots,$JACythresh,$JACytyp,\$JACfac);
    #print "From numjac ....\n";
    #pq($dfdy,$nfcalls,$JACfac);
    
    my $dFdt    = $dfdy(0,:)->flat->unpdl;
    my $dFdy    = $dfdy(1:-1,:)->unpdl;
    if (DEBUG and $verbose>=4){pq($JACfac,$nfcalls,$dFdy,$dFdt)}

    return ($dFdy,$dFdt);
}



# Required package return value:
1;
