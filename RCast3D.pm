# RCast3D.pm

#################################################################################
##
## RHex - 3D dyanmic simulation of fly casting and swinging.
## Copyright (C) 2019 Rich Miller <rich@ski.org>
##
## This file is part of RHex.
##
## RHex is free software: you can redistribute it and/or modify it under the
## terms of the GNU General Public License as published by the Free Software
## Foundation, either version 3 of the License, or (at your option) any later
## version.
##
## RHex is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
## without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
## PURPOSE.  See the GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License along with RHex.
## If not, see <https://www.gnu.org/licenses/>.
##
## RHex makes system calls to the Gnuplot executable, Copyright 1986 - 1993, 1998,
## 2004 Thomas Williams, Colin Kelley.  It makes static links to the Gnu Scientific
## Library, which is copyrighted and available under the GNU General Public License.
## In addition, RHex incorporates code from the Perl core and numerous Perl libraries,
## all of which are free software, redistributable and/or modifable under the same
## terms as Perl itself (Perl License).  Finally, the modules Brent, DiffEq, and
## Numjac in the directory RUtils are modifications and translations into Perl of
## copyrighted material.  You can find the details in the individual files.
##
##################################################################################


# BEGIN CUT & PASTE DOCUMENTATION HERE =================================================

# DESCRIPTION:  RHexCast is a graphical interface to a program that simulates the motion of a bamboo hex rod, line, leader, and fly during a cast.  The user sets parameters which specify the physical and dimensional properties of the above components as well as the time-motion of the rod handle, which is the ultimate driver of the cast.  The program outputs datafiles and cartoon images that show successive stop-action frames of the components.  Parameter settings may be saved and retrieved for easy project management.

#  The only significant restriction on the simulation is that the cast is driven and plays out in a single 2-dimensional plane (typically vertical, representing a pure overhead cast).  In addition, the ambient air is assumed to be motionless.

#  RHexCast is meant to useful for both rod design and for understanding how changes in casting stroke result in different motions of the line and leader.  As in all numerical simulation, the utility is predicting behavior without actually having to build a physical rod, fashion a line and leader, or make casts on a windless day.  In principle, the simulation may be done to any degree of resolution and the integration carried out for any time interval.  However, computer speed sets practical limits.  Perhaps surprisingly, the rod is easy to resolve adequately; it is the line and leader motion that requires most of the computing resource.  Still, with even fairly slow machines and a little patience, you can get enlightening information.

#  The casting stroke may be specified either by setting a number of parameters, or, graphically, by using any of a number of generally available drawing programs to depict a sequence of line segments that represent handle positions in successive frames taken at a fixed rate, and then saving the depiction as an SVD file.  The graphical method allows you to specify any cast at all, but is rather labor intensive.  In calibrating RHexCast in the first place, we made slow-motion videos of real casts with a particular rod, line, and leader combination, loaded the individual video frames, one at a time in the Inkscape program, drew a line segment overlying the handle (whose lower and upper ends had been highlighted with yellow tape), and then deleted the frame image, leaving just the line segment.

#  A combination of the parametric and graphical methods is also available.  One can make an SVG file as outlined above, and then parametrically morph the cast, to change the total time duration and the length and direction of the vector connecting the beginning and end locations of the rod butt.

# END CUT & PASTE DOCUMENTATION HERE =================================================





### See "About the calculation" just before the subroutine SetupIntegration() for a discussion of the general setup for the calculation.  Documentation for the individual setup and run parameters may found just below, where the fields of runParams are defined and defaulted.


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
#  17/10/01 - See RHexStatic (17/09/29).  Understood the model a bit better:  the angle theta are the dynamical variables and act at the nodes (hinges), starting at the handle top and ending at the node before the tip.  The bending at these locations creates torques that tend to straighten the angles (see GradedFiberMoments()).  The masses, however, are properly located at the segment cg's, and under the effect of gravity, they also produce torques at the nodes.  In equilibrium, these two sets of torques must cancel.  Note that there is no need for the masses to be in any particular configuration with respect to the hinges or the stretches - the connection is established by the partials matrix, in this case, dCGQs_dqs (in fact, also d2CGQs_d2thetas for Calc_pDotsKE). There remains a delicacy in that the air drag forces should more properly be applied at the segment surface resistance centers, which are generally slightly different from the segment cgs.  However, to avoid doubling the size of the partials matrices, I will content myself with putting the air drags at the cg's.
#  17/10/08 - For a while I believed that I needed to compute cartesian forces from the tension of the line on the guides.  This is wrong.  Those forces are automatically handled by the constraints.  However, it does make sense to take the length of the section of line between the reel and the first line node (say a mark on the line, always outside the rod tip) as another dynamical variable.  The position of the marked node in space is determined by the seg length and the direction defined by the two components of the initial (old-style) line segment.  To first approximation, there need not be any mass associated with the line-in-guides segment since that mass is rather well represented by the extra rod mass already computed, and all the line masses outboard cause the new segment to have momentum.  What might be gained by this extra complication is some additional shock absorbing in the line.

#  17/10/30 - Modified to use the ODE solver suite in the Gnu Scientific Library.  PerlGSL::DiffEq provides the interface.  This will allow the selection of implicit solvers, which, I hope, will make integration with realistic friction couplings possible.  It turns out to be well known that friction terms can make ODE's stiff, with the result that the usual, explicity solvers end up taking very small time steps to avoid going unstable.  There is considerable overhead in implicit solutions, especially since they require jacobian information.  Providing that analytically in the present situation would be a huge problem, but fortunately numerical methods are available.  In particular, I use RNumJac, a PDL version of Matlab's numjac() function that I wrote.

#  19/9/6 - Converted internal calculation units to CGS.

#  19/9/30 - Came to believe putting the mass at the segment cg's while putting many of the forces at the nodes was causing big numerical instabilities in the line motion.  Restored original plan of having the masses at the nodes, and putting the fluid forces there too.

### TO DO:
# Get TK::ROText to accept \r.
# Add hauling and wind velocity.


# Compile directives ==================================
package RCast3D;

use warnings;
use strict;

our $VERSION='0.01';

use Exporter 'import';
our @EXPORT = qw($rps DoSetup LoadRod LoadLine LoadLeader LoadDriver DoRun DoSave);

use Carp;

use Time::HiRes qw (time alarm sleep);
use Switch;     # WARNING: switch fails following an unrelated double-quoted string literal containing a non-backslashed forward slash.  This despite documentation to the contrary.
use File::Basename;
use Math::Spline;
use Math::Round;

# We need our own copies of all the PDL stuff.  Easier than explicitly exporting it from RHexCommon.

use PDL;
    # Import main PDL module (see PDL.pm for equivalents).  In particular, imports PDL::Math, which redefines many POSIX math functions.  To get the original, call POSIX::aFunction.

use PDL::NiceSlice;
use PDL::AutoLoader;    # MATLAB-like autoloader.
use PDL::Options;     # Good to keep in mind. See RLM.
PDL::no_clone_skip_warning;

use RUtils::DiffEq;
use RUtils::Print;
use RUtils::Plot;

use RCommon;
use RHamilton3D;
use RCommonPlot3D;

use constant EPS => 2**(-52);
my $EPS = EPS;


# Run params --------------------------------------------------------------

$verbose = 1;   # See RHexCommon for conventions.

my %runParams;
### !!!! NOTE that after changing this structure, you should delete the widget prefs file.
our $rps = \%runParams;

# SPECIFIC DISCUSSION OF PARAMETERS, TYPICAL AND DEFAULT VALUES:

$rps->{file} = {
    rCast    => "RHexCast3D v1.0, 4/7/2019",     # The existence of this field is used for verification that input file is a sink settings file.  It's contents don't matter    settings    => "RHexCast3D.prefs",
    settings    => "SpecFiles_Preference/RHexCast3D.prefs",
    rod         => "",
    line        => "",
    driver        => "",
    save        => "",
        # If non-empty, there is something to plot.
};

$rps->{rod} = {
    numSegs            => 9,
        # Starts at the start of the action (typically just at the top of the handle) node and includes the tip node.  If set to 1, there is no rod, and the line is attached directly to the handle (possibly useful for testing).  Must be at least 1.
    segExponent         => 1.25,
        # Bigger than 1 concentrates more rod nodes near rod tip.
	rodLenFt			=> 9,
	actionLenFt			=> 8.25,
	numPieces			=> 2,
    sectionItem     	=> 0,
    sectionName			=> "section - hex",
	buttDiamIn			=> 0.350,
	tipDiamIn			=> 0.080,
    zeroFiberThicknessIn	=> 0.0, # Zero for uniform.  Otherwise, assumes linear dropoff in fiber count as you move in from the enamel.  Then this is inches to drop to 0.  Roughly, this is the usable culm thickness.  Lower numbers soften the rod generally, but stiffen the tip relative to the base.
    maxWallThicknessIn  => 1,   # For hollow core rods.  Larger than max half-diam for no max.
    ferruleKsMult       => 1, # Zero for no increment.  1 effectively doubles.
    vAndGMultiplier     => 0, # A multiple of the segment surface area to account the weight of the  varnish and guides.  Has dimension of oz/in^2.
	densityLbFt3        => 64,
    elasticModulusPSI   => 6e6,
    # Rod maker's estimate < 5e6 psi.  8e6 matches DZ's Sir D pretty well.  If anything it is a bit too flexible. This is a problem since the published numbers (except for one Garrison outlier) are all < 6e6.  https://en.wikipedia.org/wiki/Young%27s_modulus, for table including wood and nylon.  http://bamboo.wikispaces.asu.edu/4.+Bamboo+Properties, http://www.bamboorodmaking.com/html/rod_design_-_modulus_of_elasti.html  1.1e7 much too stiff, dominates line initially.
    dampingModulusStretchPSI   => 100,
        # Scaled to rod diameter the same way the elastic modulus is. I should try to find experimental numbers for this.  Given the way I use it, to construct damping coefficients, in numerical experiments with no line weight, 1e7 seems a bit too much, 1e6 too little.  If this is set much lower, the rod tip just rotates crazily at the end of the power stroke.
    dampingModulusBendPSI   => 100,
		# This may arise due to a completely different mechanism from stretch, since here fibers must slip past one another.  Also, if the friction is non-linear with velocity, this becomes much more complex than the stretching case.
    totalThetaDeg		=> 0,
        # 0 for straight initial rod.
};

$rps->{line} = {
    numSegs                => 5,
        # Starts first node outboard the rod tip node and runs to the end of the line (including leader and tippet).
    segExponent             => 1.33,
    # Bigger than 1 concentrates more line nodes near rod tip.
    activeLenFt             => 20,
    # Total desired length from rod tip to leader.
    identifier              => "",
    nomWtGrsPerFt            => 6,
    # This is the nominal.  If you are reading from a file, must be an integer.
	estimatedSpGrav		=> 0.8,
    # Only used if line read from a file and finds no diameters.
    nomDiameterIn           => 0.060,
    coreDiameterIn          => 0.020,
    # Make a guess.  Used in computing effective Hook's Law constant from nominal elastic modulus.
    coreElasticModulusPSI   => 1.52e5,        # 2.5e5 seems not bad, but the line hangs in a curve to start so ??
    # I measured the painted 4 wt line (tip 12'), and got corresponding to assumed line core diam of 0.02", EM = 1.52e5.
    # Try to measure this.  Ultimately, it is probably just the modulus of the core, with the coating not contributing that much.  0.2 for 4 wt line, 8' long is ok.  For 20' 7wt, more like 2.  This probably should scale with nominal line weight.   A tabulated value I found for Polyamides Nylon 66 is 1600 to 3800 MPa (230,000 to 550,000 psi.)
    dampingModulusPSI          => 10000,
    # Cf rod damping modulus.  I don't really understand this, but numbers different bigger from 10000 slow the integrator way down.  For the moment, since I don't know how to get the this number for the various leader and tippet materials, I am taking this value for those as well.
	preTensionOz		=> 0,
	# Pre-stretch line to this tension to balance initial rod bend.
    angle0Deg			=> -90,
    # Orientation of straight line between rod tip and fly, relative to vertical.  So -90 for horizontal with cast to the right.
    curve0InvFt			=> 0,
    # The inital total line shape to a constant curve having that value as curvature (1/radius of curvature).  Positive is concave up.
	
};



$rps->{leader} = {
    idx                 => 1,   # Index in the leader menu.
    text            => "leader - level",
    lenFt           => 12,
    wtGrsPerFt      => 8,   # Grains/ft
    diamIn          => 0.020,   # Inches
    coreDiamIn      => 0.010,
};


$rps->{tippet} = {
    lenFt               => 2,
    idx                 => 1,   # Index in the leader menu.
    text                => "tippet - mono",
    diamIn        => 0.011,     #  0.011 - diam in thousanths = "X" rating
};

$rps->{fly} = {
    wtGr            => 1,
    nomDiamIn       => 0.25,
    nomLenIn        => 0.25,
};


$rps->{ambient} = {
    nominalG         => 1,
        # Set to 1 to include effect of vertical gravity, 0 is no gravity, any value ok.
    dragSpecsNormal          => "11,-0.74,1.2",
    dragSpecsAxial           => "11,-0.74,0.01",
};


$rps->{driver} = {
	startTime				=> 0,	# Same as power start time
    powerVMaxTime			=> 0.2,
    powerEndTime			=> 0.3,
    driftStartTime			=> 0.3.01,
	endTime					=> 0.5,	# Same as drift end time
	
	# Location of handle top, "X,Y,Z"
    powerStartCoordsIn		=> "0,0,72",
    powerEndCoordsIn		=> "12,0,60",
    powerPivotCoordsIn		=> "0,0,60",
    powerCurvInvIn			=> 0,
    powerSkewness           => 0,   # Positive is more curved later.
	powerHandleStartDeg		=> -40,
	powerHandleEndDeg		=> -20,
		# In plane of power stroke, rel line from pivot.
    powerHandleSkewness		=> 0,   # Positive is more curved later.

    #driftEndCoordsIn		=> "12,0,50",	# Drift starts at power end coords.
	#driftCurveInvIn			=> 0,
	driftHandleEndDeg		=> 0,	# Drift wrist starts where power wrist ends.
    driftVelSkewness        => 0,   # Positive is faster later.
	
    showTrackPlot           => 1,
    plotSplines				=> 0,
};

$rps->{holding} = {
    releaseDelay		=> 0.167,
        # How long after t0 to release the line tip.  -1 for before start of integration.
    releaseDuration		=> 0.004,
        # Duration from start to end of release.
	springConstOzPerIn		=> 100,
	dampingConstOzSecPerIn	=> 0,
};


$rps->{integration} = {
    t0              => 0.0,     # initial time
    t1              => 1.0,     # final time.  Typically, set this to be longer than the driven time.
    dt0             => 0.0001,    # initial time step - better too small, too large crashes.
    minDt           => 1.e-7,   # abandon integration and return if seemingly stuck.    
    plotDt          => 1/60,    # Set to 0 to plot all returned times.

    eps             => 1.e-6,   # Target error.  Typically 1.e-6.
    
    stepperItem     => 0,
    stepperName     => "msbdf_j",
    
    showLineVXs     => 0,
    plotLineVYs     => 0,
    plotLineVAs     => 0,
    plotLineVNs     => 0,
    plotLine_rDots  => 0,

    savePlot    => 1,
    saveData    => 1,

	switchEachPlotDt	=> 0,
    debugVerboseName    => "debugVerbose - 4",
	verboseName			=> "verbose - 2",
};


# Package internal global variables ---------------------
#my $calculateAirDrag            = 0;
my ($dateTimeLong,$dateTimeShort,$runIdentifier);


#print Data::Dump::dump(\%runParams); print "\n";



# Package subroutines ------------------------------------------

sub DoSetup {
    
    ## RHexCast is organized differently from RHexStatic.  Here, except for the preference file, files are not loaded when selected, but rather, loaded when run is called.  This lets the load functions use parameter settings to modify the load -- what you see (in the widget) is what you get.  In particular, widget value suggestions contained in the rod file are ignored.  Required non-widget values there (RodLength, Actionlength, NumSections, which are NOT widget parameters) are loaded.  This procedure allows the preference file to dominate.  Suggestions in the rod files should indicate details of that particular rod construction, which the user can bring over into the widget via the preferences file or direct setting, as desired.
    
    ### WARNING: pdl's are passed by reference.  So if you want the behavior as in C's declaring an argument constant, you must use $xx->copy in the function body.  $xx->sever doesn't seem to do it!
    ### No, it's subtler than that.  In the subroutine you need to explicitly use .= to back propagate!
    ### Indeed, you seem to need .= to assign anything less than the whole thing, otherwise you just
	
    PrintSeparator("*** Setting up the solver run ***",0,$verbose>=2);
        
    $dateTimeLong = scalar(localtime);
    if ($verbose>=2){print "\n\n$dateTimeLong\n"}
    
    my($date,$time) = ShortDateTime;
    $dateTimeShort = sprintf("(%06d_%06d)",$date,$time);
    
    $runIdentifier = 'RUN'.$dateTimeShort;
    
    PrintSeparator("INITIALIZING RUN - $dateTimeLong");
    
    if ($verbose>=5){print Data::Dump::dump(\%runParams); print "\n"}
    
    
    my $ok = CheckParams();
    if (!$ok){print "ERROR: Bad params.  Cannot proceed.\n\n";return 0};
    
    if (!LoadRod($rps->{file}{rod})){$ok = 0};
    if (!LoadLine($rps->{file}{line})){$ok = 0};
    if (!LoadLeader($rps->{file}{leader})){$ok = 0};
    LoadTippet();   # Can't fail.
    if (!LoadDriver($rps->{file}{driver})){$ok = 0};
    if (!$ok){print "ERROR: LOADIING FAILURE.  Cannot proceed.\n\n"; return 0};
    
    SetupModel();
    SetupDriver();
    SetupIntegration();
    
    return 1;
}


sub CheckParams{

    
    PrintSeparator("Checking Params");

    #ccc
    
    my $ok = 1;
    my ($str,$val);
    
    $str = "numSegs"; $val = $rps->{rod}{$str};
	#print "val=$val\n";die;
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: rod $str = $val - Number of segments must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 7 or $val > 12)){print "WARNING: rod $str = $val - Typical range is [7,12].\n"}
    
    $str = "segExponent"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val <= 0){$ok=0; print "ERROR: rod $str = $val - Seg exponent must be positive.\n"}
    elsif($verbose>=1 and ($val < 0.5 or $val > 2)){print "WARNING: rod $str = $val - Typical range is [0.5,2].\n"}
	
    $str = "rodLenFt"; $val = $rps->{rod}{$str};
	my $rodLenFt = $val;
    if ($val eq '' or $val <= 0){$ok=0; print "ERROR: $str = $val - Length must be positive.\n"}
    elsif($verbose>=1 and ($val < 6 or $val > 14)){print "WARNING: $str = $val - Typical range is [6,14].\n"}
	
    $str = "actionLenFt"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val >= $rodLenFt){$ok=0; print "ERROR: $str = $val - Action length must be less than rod length.\n"}
    elsif($verbose>=1 and (abs($rodLenFt-$val) < 0.75 or abs($rodLenFt-$val) > 1.5)){print "WARNING: $str = $val - Typical range is [5.25,12.5].\n"}
	
    $str = "numPieces"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val <= 0 or $val-int($val)!= 0){$ok=0; print "ERROR: $str = $val - Number of rod pieces must be a positive integer.\n"}
    elsif($verbose>=1 and ($val < 2 or $val > 5)){print "WARNING: $str = $val - Typical range is [2,5].\n"}
	
    $str = "buttDiamIn"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val <= 0){$ok=0; print "ERROR: $str = $val - Butt diameter must be positive.\n"}
    elsif($verbose>=1 and ($val < 0.250 or $val > 0.450)){print "WARNING: $str = $val - Typical range is [0.250,0.450].\n"}

    $str = "tipDiamIn"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val <= 0){$ok=0; print "ERROR: $str = $val - Tip diameter must be positive.\n"}
    elsif($verbose>=1 and ($val < 0.060 or $val > 0.100)){print "WARNING: $str = $val - Typical range is [0.060,0.100].\n"}

    $str = "zeroFiberThicknessIn"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val != 0 and ($val < 0.2 or $val > 0.4))){print "WARNING: $str = $val - If not zero, typical range is [0.200,0.400].\n"}
    
    $str = "maxWallThicknessIn"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val != 0 and ($val < 0.2 or $val > 0.4))){print "WARNING: $str = $val - If not zero, typical range is [0.200,0.400].\n"}
	
    $str = "ferruleKsMult"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=0 and $val > 1){print "WARNING: $str = $val - Typical range is [0,1].\n"}
    
    $str = "vAndGMultiplier"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and $val > 0.002){print "WARNING: $str = $val - Typical range is [0,0.002].\n"}
	
    $str = "densityLbFt3"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val <= 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 50 or $val > 60)){print "WARNING: $str = $val - Typical range is [50,60].\n"}
    
    $str = "elasticModulusPSI"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val <= 0){$ok=0; print "ERROR: rod $str = $val - Elastic modulus must be positive.\n"}
    elsif($verbose>=1 and ($val < 2e6 or $val > 8e6)){print "WARNING: rod $str = $val - Typical range is [2e6,8e6].\n"}
    
    $str = "dampingModulusStretchPSI"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: rod $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 50 or $val > 200)){print "WARNING: rod $str = $val - Typical range is [50,200].\n"}
    
    $str = "dampingModulusBendPSI"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: rod $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 50 or $val > 200)){print "WARNING: rpd $str = $val - Typical range is [50,200].  In static emulation, 3.5e3 gives 50% reduction per cycle and 2e4 is critically damped.\n"}
 
	
    $str = "totalThetaDeg"; $val = eval($rps->{rod}{$str});
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: rod $str = $val - Initial curvature must be non-negative.\n"}
    #    elsif($verbose>=1 and ($val < 0.5 or $val > 2)){print "junk\n"}
    #elsif($verbose>=1 and $val > $pi/4){print "junk1\n"}
    elsif($verbose>=1 and $val > 90){print "WARNING: rod $str = $val - 0 is straight, positive values start rod concave toward the initial line direction.  Typical range is [0,90"}
	
	my $totalLineLenFt = 0;
    
    $str = "numSegs"; $val = $rps->{line}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: line $str = $val - Number of segments must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 2 or $val > 15)){print "WARNING: line $str = $val - Typical range is [2,15].\n"}
    
    $str = "segExponent"; $val = $rps->{line}{$str};
    if ($val eq '' or $val <= 0){$ok=0; print "ERROR: line $str = $val - Seg exponent must be positive.\n"}
    elsif($verbose>=1 and ($val < 1 or $val > 2)){print "WARNING: line $str = $val - Typical range is [1,2].\n"}
    
    $str = "activeLenFt"; $val = $rps->{line}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: line $str = $val - length must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 10 or $val > 50)){print "WARNING: line $str = $val - Typical range is [10,50].\n"}
	if ($ok){$totalLineLenFt += $val}
    
     $str = "nomWtGrsPerFt"; $val = $rps->{line}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and $val > 10){print "WARNING: $str = $val - Typical range is [0,10].\n"}
    
    $str = "estimatedSpGrav"; $val = $rps->{line}{$str};
    if ($val eq '' or $val <= 0){$ok=0; print "ERROR: $str = $val - Must be positive.\n"}
    elsif($verbose>=1 and ($val < 0.5 or $val > 1.5)){print "WARNING: $str = $val - Typical range is [0.5,1.5].\n"}
    
   $str = "coreDiameterIn"; $val = $rps->{line}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 0.01 or $val > 0.05)){print "WARNING: $str = $val - Typical range is [0.01,0.05].\n"}
    
    $str = "coreElasticModulusPSI"; $val = $rps->{line}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: line $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 1e5 or $val > 4e5)){print "WARNING: line $str = $val - Typical range is [1e5,4e5].\n"}
    
    $str = "dampingModulusPSI"; $val = $rps->{line}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: line $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 0 or $val > 1e5)){print "WARNING: line $str = $val - Typical range is [0,1e5].\n"}
    
    $str = "lenFt"; $val = $rps->{leader}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: leader $str = $val - leader length must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 5 or $val > 15)){print "WARNING: leader $str = $val - Typical range is [5,15].\n"}
	if ($ok){$totalLineLenFt += $val}	# NEEDS WORK.  WILL GET NOTHING IF LEADER SET FROM MENU.
    
    $str = "wtGrsPerFt"; $val = $rps->{leader}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: leader $str = $val - weights must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 5 or $val > 15)){print "WARNING: leader $str = $val - Typical range is [7,18].\n"}
    
    $str = "diamIn"; $val = $rps->{leader}{$str};
    if ($val eq '' or $val <= 0){$ok=0; print "ERROR: leader $str = $val - diams must be positive.\n"}
    elsif($verbose>=1 and ($val < 0.004 or $val > 0.020)){print "WARNING: leader $str = $val - Typical range is [0.004,0.020].\n"}
    
    $str = "lenFt"; $val = $rps->{tippet}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: tippet $str = $val - lengths must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 2 or $val > 12)){print "WARNING: tippet $str = $val - Typical range is [2,12].\n"}
	if ($ok){$totalLineLenFt += $val}
    
	
    $str = "diamIn"; $val = $rps->{tippet}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: tippet $str = $val - diams must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 0.004 or $val > 0.012)){print "WARNING: tippet $str = $val - Typical range is [0.004,0.012].\n"}
    
    $str = "wtGr"; $val = $rps->{fly}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: fly $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and $val > 926){print "WARNING: fly $str = $val - Kluge for testing, 2 oz = 926 grains.  Typical real fly range is [0,5]\n"}
    
    $str = "nomDiamIn"; $val = $rps->{fly}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: fly $str = $val - Fly nom diam must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 0 or $val > 0.25)){print "WARNING: fly $str = $val - Typical range is [0.1,0.25].\n"}
    
    $str = "nomLenIn"; $val = $rps->{fly}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: fly $str = $val - Fly nom diam must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 0 or $val > 1)){print "WARNING: fly $str = $val - Typical range is [0.25,1].\n"}
    
    $str = "nominalG"; $val = $rps->{ambient}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Gravity must be must be non-negative.\n"}
    elsif($verbose>=1 and ($val != 1)){print "WARNING: $str = $val - Typical value is 1.\n"}
    
    my ($tt,$a,$b,$c,$err);
    $str = "dragSpecsNormal";
    $tt = Str2Vect($rps->{ambient}{$str});
    if ($tt->nelem != 3) {
        $ok=0;
        print "ERROR: $str must be of the form MULT,POWER,MIN where the first two are greater than zero and the last is greater than or equal to zero.\n";
    } else {
        $a = $tt(0)->sclr; $b = $tt(1)->sclr; $c = $tt(2)->sclr;
        if ($verbose>=1 and ($a<23 or $a>25 or $b<-1.05 or $b>-0.95 or $c<0.9 or $c>1.1)){print "WARNING: $str = $a,$b,$c - Experimentally measured values are 24,-1,1.\n"}
    }
    
    $str = "dragSpecsAxial";
    $tt = Str2Vect($rps->{ambient}{$str});
    if ($tt->nelem != 3) {
        $ok=0;
        print "ERROR: $str must be of the form MULT,POWER,MIN where the first two are greater than zero and the last is greater than or equal to zero.\n";
    } else {
        $a = $tt(0)->sclr; $b = $tt(1)->sclr; $c = $tt(2)->sclr;
        if ($verbose>=1 and ($a<23 or $a>25 or $b<-1.05 or $b>-0.95 or $c<0.005 or $c>0.1)){print "WARNING: $str = $a,$b,$c - Experiments are unclear, try  24,-1,0.01.  The last value should be much less than the equivalent value in the normal spec.\n"}
    }

    $str = "angle0Deg"; $val = eval($rps->{line}{$str});
	if ($val eq '' or $val <= -180 or $val > 180){$ok=0; print "ERROR: line $str = $val - Initial line angle must be in the range (-180,180].\n"}
    if($verbose>=1 and ($val < -110 or $val > -70)){print "WARNING: line $str = $val -90 is horizontal to the left, usual range is [-110,-70].\n"}
 
	$str = "curve0InvFt"; $val = eval($rps->{line}{$str});
	if ($val eq '' or abs($val)>1/$totalLineLenFt){$ok=0; print "ERROR: line $str = $val - Curvature must be no greater than the reciprocal of the total line length (here 1\/$totalLineLenFt).\n"}
    elsif($verbose>=1 and ($val > 0 or abs($val) > 1/(2*$totalLineLenFt))){my $bound = 1/(2*$totalLineLenFt);print "WARNING: line $str = $val - 0 is straight, negative is concave up.  Typical range is [-1\/(2*total line length including leader)=(here,$bound) ,0].\n"}
    
    $str = "releaseDelay"; $val = $rps->{holding}{$str};
    if ($val eq ''){$ok=0; print "ERROR: $str = $val - Must be defined.\n"}
    elsif ($rps->{line}{numSegs} <= 0 and $val >= 0){$ok=0; print "ERROR: $str = $val -	Unless there are line segments, there can be no holding, so in that case, release delay must be negative.\n"}
    elsif($verbose>=1 and ($val < 0.15 or $val > 0.2)){print "WARNING: $str = $val - Typical range is [0.150,0.200]. Values less than zero turn holding off.\n"}
	if ($val ne ''){$rps->{integration}{$str} = DecimalRound($val)}
	
    $str = "releaseDuration"; $val = $rps->{holding}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val <= 0.001 or $val > 0.01)){print "WARNING: $str = $val - Numbers near 0.005 work well. Very small or zero may cause integrator problems.\n"}
	if ($val ne ''){$rps->{integration}{$str} = DecimalRound($val)}
	
    $str = "springConstOzPerIn"; $val = $rps->{holding}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: holding $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 10 or $val > 1000)){print "WARNING: holding $str = $val - Typical range is [10,100].\n"}
    
    $str = "dampingConstOzSecPerIn"; $val = $rps->{holding}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: holding $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 1 or $val > 100)){print "WARNING: holding $str = $val - Typical range is [1,100].\n"}
	
	if ($rps->{driver}{startTime} >= $rps->{driver}{endTime}){
		print "WARNING:  motion start time greater or equal to motion end time means no rod tip motion will happen.  Resetting end time to equal start time.\n";
		$rps->{driver}{endTime} = $rps->{driver}{startTime};
	}
	
	if ($rps->{driver}{startTime} eq '' or $rps->{driver}{powerVMaxTime} eq '' or $rps->{driver}{powerEndTime} eq '' or $rps->{driver}{driftStartTime} eq '' or $rps->{driver}{endTime} eq '' ){$ok=0; print "ERROR: All motion times must be numerical values.\n"}
	
	if ($rps->{driver}{startTime} > $rps->{driver}{powerVMaxTime} or
		$rps->{driver}{powerVMaxTime} > $rps->{driver}{powerEndTime} or
		$rps->{driver}{powerEndTime} > $rps->{driver}{driftStartTime} or
		$rps->{driver}{driftStartTime} > $rps->{driver}{endTime}){
			$ok=0;
			print "ERROR: Driver times must be non-decreasing as listed.\n";
	}
	
	if ($rps->{driver}{startTime} == $rps->{driver}{endTime} and
		(	$rps->{driver}{startTime} != $rps->{driver}{powerVMaxTime} or
			$rps->{driver}{powerVMaxTime} != $rps->{driver}{powerEndTime} or
			$rps->{driver}{powerEndTime} != $rps->{driver}{driftStartTime} or
			$rps->{driver}{driftStartTime} != $rps->{driver}{endTime} )){
			$ok=0;
			print "ERROR: If driver start and end times are equal, all times must be.\n";
	}
	
    $str = "powerStartCoordsIn";
    my $ss = Str2Vect($rps->{driver}{$str});
    if ($ss->nelem != 3) {
        $ok=0;
        print "ERROR: $str must be of the form X,Y,Z.\n";
    }
    
    $str = "powerEndCoordsIn";
    my $ee = Str2Vect($rps->{driver}{$str});
    if ($ee->nelem != 3) {
        $ok=0;
        print "ERROR: $str must be of the form X,Y,Z.\n";
    }

    my $trackLen = sqrt(sum($ee-$ss)**2);
    if ($trackLen > 30){print "WARNING: Track start-end length = $trackLen.  This is larger than expected.\n"}

    $str = "powerPivotCoordsIn";
    my $ff = Str2Vect($rps->{driver}{$str});
    if ($ff->nelem != 3) {
        $ok=0;
        print "ERROR: $str must be of the form X,Y,Z.\n";
    } else {
        $a = $ff(0)->sclr; $b = $ff(1)->sclr; $c = $ff(2)->sclr;
        my $sLen = sqrt(sum($ss-$ff)**2);
        my $eLen = sqrt(sum($ee-$ff)**2);
 #       if ($verbose and ($a<0 or $a>80 or abs($b)>40 or $c<0 or $c>80)){print "WARNING: $str = $a,$b,$c - Typical values are the range of positions of the shoulder.\n"}
 # Maybe later put in something.
    }
	
	# Check that the start and pivot points are not identical:
	my $sv = $ss - $ff;
	if (sqrt(sum($sv)**2) == 0){
		$ok=0;
		print "ERROR: Start and pivot points must not be identical.\n";
	}
	
	# Check that the start, end and pivot points are not co-linear:
	my $ev = $ee - $ff;
	
	my $planeOK = ((($sv(1)*$ev(2)-$sv(2)*$ev(1))**2 +
		($sv(0)*$ev(2)-$sv(2)*$ev(0))**2 +
		($sv(0)*$ev(1)-$sv(1)*$ev(0))**2) != 0);
	
    my $tLen = sqrt(sum(($ee-$ss)**2));
	if (!$planeOK) {
		if ($tLen){
			$ok=0;
			print "ERROR: Start, end and pivot points must not be co-linear unless the start and end points are identical.\n";
		} else {
			print "WARNING: Start and end points are identical.  NO HANDLE MOTION IS ALLOWED IN THIS CASE.\n";
		}
	}
	
    $str = "powerCurvInvIn"; $val = eval($rps->{driver}{$str});
    if ($val eq '' or ($tLen and abs($val) > 2/$tLen)){$ok=0; print "ERROR: $str = $val - track curvature must be in the range (-2\/trackLen,2\/trackLen).  Positive curvature is away from the pivot.\n"}
    
    $str = "powerSkewness"; $val = $rps->{driver}{$str};
	if ($val eq ''){$ok=0; print "ERROR: $str = $val - Must be a numerical value.\n"}
    if($verbose>=1 and ($val < -0.25 or $val > 0.25)){print "WARNING: $str = $val - Positive values peak later.  Typical range is [-0.25,0.25].\n"}

    $str = "powerHandleStartDeg"; $val = $rps->{driver}{$str};
    if ($val eq '' or $val < -90 or $val > 90){$ok=0; print "ERROR: $str = $val - Must be in [-90,90].\n"}
    elsif($verbose>=1 and ($val < -40 or $val > -10)){print "WARNING: $str = $val - Typical range is [-40,-10].\n"}
    
    $str = "powerHandleEndDeg"; $val = $rps->{driver}{$str};
    if ($val eq '' or $val < -90 or $val > 90){$ok=0; print "ERROR: $str = $val - Must be in [-90,90].\n"}
    elsif($verbose>=1 and ($val < 40 or $val > 70)){print "WARNING: $str = $val - Typical range is [40,70].\n"}
    
    $str = "powerHandleSkewness"; $val = $rps->{driver}{$str};
	if ($val eq ''){$ok=0; print "ERROR: $str = $val - Must be a numerical value.\n"}
    if($verbose>=1 and ($val < -1 or $val > 1)){print "WARNING: $str = $val - Positive values peak later.  Typical range is [-1,1].\n"}

    $str = "driftHandleEndDeg"; $val = $rps->{driver}{$str};
    if ($val eq '' or $val < -90 or $val > 135){$ok=0; print "ERROR: $str = $val - Must be in [-90,90].\n"}
    elsif($verbose>=1 and ($val < 40 or $val > 90)){print "WARNING: $str = $val - Typical range is [40,90].\n"}
	
    $str = "driftVelSkewness"; $val = $rps->{driver}{$str};
	if ($val eq ''){$ok=0; print "ERROR: $str = $val - Must be a numerical value.\n"}
    if($verbose>=1 and ($val < -1 or $val > 1)){print "WARNING: $str = $val - Positive values peak later.  Typical range is [-1,1].\n"}

    $str = "t0"; $val = eval($rps->{integration}{$str});
	if ($val eq ''){$ok=0; print "ERROR: $str = $val - Must be a numerical value.\n"}
    if($verbose>=1 and ($val != 0)){print "WARNING: $str = $val - Typical integration start time is 0.\n"}
	if ($val ne ''){$rps->{integration}{$str} = DecimalRound($val)}
	my $t0 = $val;

    $str = "t1"; $val = eval($rps->{integration}{$str});
	if ($val eq '' or $val <= $t0){$ok = 0; print "ERROR: Run time must be positive.  Check values of t0 and t1.\n"}
	if ($val eq ''){$ok=0; print "ERROR: $str = $val - Must be a numerical value.\n"}
    if($verbose>=1 and ($val < 0.5 or $val > 2)){print "WARNING: $str = $val - Typical integration end time is in the range [0.5,2].\n"}
	if ($val ne ''){$rps->{integration}{$str} = DecimalRound($val)}

    $str = "minDt"; $val = eval($rps->{integration}{$str});
	if ($val eq '' or $val <= 0){$ok=0; print "ERROR: $str = $val - Must be a non-negative number.\n"}
    if($verbose>=1 and ($val < 1.e-8 or $val > 1.e-6)){print "WARNING: $str = $val - Time step less than which the integrator will give up.  Typical range is [1e-8,1e-6].\n"}
	
     $str = "plotDt"; $val = eval($rps->{integration}{$str});
	if ($val eq '' or $val <= 0){$ok=0; print "ERROR: $str = $val - Must be a non-negative number.\n"}
    if($verbose>=1 and ($val < 0.01 or $val > 0.10)){print "WARNING: $str = $val - Intervals at which intergrator results are reported and traces are plotted.  Typical values are in the range [0.010,0.100].\n"}
	if ($val ne ''){$rps->{integration}{$str} = DecimalRound($val)}

	
    return $ok;
}


my $rodIdentifier;
my ($rodLenFt,$rodActionLenFt,$numPieces,$sectionType);
my ($loadedRodDiamsIn,$loadedThetas);
my ($loadedState,$loadedRodSegLens,$loadedLineSegLens,$loadedT0);
my ($dXs,$dYs,$dZs);


sub LoadRod {
    my ($rodFile) = @_;
    
    ## Process rodFile if defined, otherwise set thetas and diams from defaults.  However, if an integration state (and its corresponding rod and line segment lengths) is available, we will use them to initialize the integration dynamical variables, ignoring other initial location specifiers.  Next preferred, if the 3D rod offsets are present, use them to set the initial configuration.  Finally, use flex if present.

    PrintSeparator("Loading rod");

    my $ok = 1;
	my $gotOffsets = 0;

    ($loadedRodDiamsIn,$loadedThetas,$loadedState,
     $loadedRodSegLens,$loadedLineSegLens,$loadedT0,
	 $dXs,$dYs,$dZs) = map {zeros(0)} (0..8);

    my $tNumRodNodes = 31;
        # Just temporary, big enough to give ok resolution for later splining.  Will be overwritten if rod is loaded.

    if ($rodFile) {

		my $inData;
		# See perldoc perlvar, variables related to file management.
        open INFILE, "< $rodFile" or $ok = 0;
       	if (!$ok){print $!;return 0}
		{
			local $/;
        	$inData = <INFILE>;
		}
        close INFILE;
        
        if ($verbose>=1){print "Data from $rodFile.\n"}
        if ($verbose>=4){print "inData:\n\t$inData\n"}
        
        if ($inData =~ m/^Identifier:\t(\S*).*\n/mo)
            {$rodIdentifier = $1}
        elsif ($inData =~ m/^Rod:\t(\S*).*\n/mo)
            {$rodIdentifier = $1}

        if ($verbose>=2){print "rodID = $rodIdentifier\n"}
        

        # Look for rod params in the file.  If found, overwrite globals or widget fields:
        $rodLenFt        = GetValueFromDataString($inData,"RodLength","first");
        if (!defined($rodLenFt)){$ok = 0; print "ERROR: Unable to find RodLength in $rodFile.\n"}

 		$rps->{rod}{rodLenFt} = $rodLenFt;
 
        $rodActionLenFt     = GetValueFromDataString($inData,"ActionLength","first");
        if (!defined($rodActionLenFt)){$ok = 0; print "ERROR: Unable to find ActionLength in $rodFile.\n"}

  		$rps->{rod}{actionLenFt} = $rodActionLenFt;
 
		$numPieces        = GetValueFromDataString($inData,"NumPieces","first");
        if (!defined($numPieces)){$numPieces = 1; if ($verbose>=1){print "Warning: Unable to find NumPieces in $rodFile.  Setting NumPieces=1.\n"};}
        
 		$rps->{rod}{numPieces} = $numPieces;
 
		$sectionType        = GetWordFromDataString($inData,"SectionType","first");
        if (!defined($sectionType)){$sectionType = "hex"; if ($verbose>=1){print "Warning: Unable to find SectionType in $rodFile.  Setting SectionType=hex.\n"};}
		
		$rps->{rod}{sectionName} = "section - " . $sectionType;
 
        my $tActionLen = 12*$rodActionLenFt;     # I need it (in inches) here.

        # In order to achieve better reproducibility by avoiding spline fitting when possible, if calculational arrays are available, use them in preference to station data:
            
        # Try to extract a calculated taper (diams) from the file.  These are assumed to be uniformly spaced.
        $loadedRodDiamsIn = GetMatFromDataString($inData,"Taper","last");

        if ($loadedRodDiamsIn->isempty) {

            # Try to pull a x stations out of the file:
            my $statXs = GetMatFromDataString($inData,"X_station","first");

            if ($statXs->isempty){$ok = 0; print "Error:  If Taper data is not present in file, then X_station and Taper_station data must be there.\n"}

            # Look for the corresponding taper stations:
            my $statDiams = GetMatFromDataString($inData,"Taper_station","first");

            if ($statDiams->isempty){$ok = 0; print "Error: If Taper data is not present in file, then X_station and Taper_station data must be there.\n"}
            if ($statXs->nelem != $statDiams->nelem){$ok = 0; print "Error: X_station and Taper_station sizes must agree.\n"}

            # Use station data to set diams via spline interpolation.
            $loadedRodDiamsIn = StationDataToDiams($statXs,$statDiams,$tActionLen,$tNumRodNodes);
            if ($verbose>=2){print "Diams set from station data.\n"}
        }
		
        # Look for integration state data in the file.  If found, use it in preference to anything else.  Expected to be used for the continuation of a previous integration.  To make sense of this, at least numRodNodes, numLineNodes, and segLens must be also preserved and read in.
        $loadedState = GetMatFromDataString($inData,"State","last");
		if (!$loadedState->isempty) { # the state was loaded.

            $loadedRodSegLens    = GetMatFromDataString($inData,"RodSegLengths");
            $loadedLineSegLens   = GetMatFromDataString($inData,"LineSegLengths");
            
            $loadedT0 = GetMatFromDataString($inData,"Time");
            pq($loadedT0);

		} else {	# No loaded state, see if there is offset or flex data:

			$dXs = GetMatFromDataString($inData,"DX");

			if (!$dXs->isempty){  # Got DX

				$dZs = GetMatFromDataString($inData,"DZ");

				if (!$dZs->isempty){	# Got DZ
				
					if ($dXs->nelem != $dZs->nelem){$ok = 0; print "Error:  If DX is present, so must be DZ, and their sizes must be equal.\n"}
					else {
						$dYs = GetMatFromDataString($inData,"DY");
						
						if (!$dYs->isempty){	# Got DY
						
							if ($dXs->nelem != $dYs->nelem){$ok = 0; print "Error:  If both DX and DY are present, they must have the same sizes.\n"}
							else {
								# Success.  Got offsets, No further op necessary.
								$gotOffsets = 1;
								#pq($dXs,$dYs,$dZs);
							}
						} else {
							if ($verbose>=2){print "Found DX and DZ but not DY.  Will construct thetas from the found offsets.\n"}
							$dYs = zeros($dXs);
							my ($tThetas,$tSegLens) = OffsetsToThetasAndSegs($dXs,$dZs);
							$loadedThetas = ResampleThetas($tThetas,$tSegLens,$tNumRodNodes);
								# To make the seg lens uniform.
						}
					}	# end got DX and DZ.
					
				} else {	# Got DX but not DZ. Check for 2D setup where there is DY.
				
					$dYs = GetMatFromDataString($inData,"DY");
					
					if (!$dYs->isempty){	# Got DY
					
						if ($dXs->nelem != $dYs->nelem){$ok = 0; print "Error:  If both DX and DY are present, they must have the same sizes.\n"}
						else {
							if ($verbose>=2){print "Found DX and DY but not DZ.  Will construct thetas from the found offsets, swapping DY and DZ.\n"}
							$dZs = $dYs;
							$dYs = zeros($dZs);
							my ($tThetas,$tSegLens) = OffsetsToThetasAndSegs($dXs,$dZs);
							$loadedThetas = ResampleThetas($tThetas,$tSegLens,$tNumRodNodes);
								# To make the seg lens uniform.
								if (DEBUG and $verbose>=3){pq($dXs,$dYs,$dZs,$loadedThetas)}
						}
					} else {
						print "Found DX but not DY or DZ.  Cannot work from offsets.\n";
					}
				}	# end DX but no DZ.
			}	# end got DX.
			

			if (!$gotOffsets and $loadedThetas->isempty){	# Couldn't work with offsets, see if there is a flex array:

				$loadedThetas = GetMatFromDataString($inData,"Flex");
				if (!$loadedThetas->isempty and $verbose>=2){print "Thetas set from flex.\n"}
				
				# To avoid later confusion, get rid of any offsets we might have gotten:
				($dXs,$dYs,$dZs) = map {zeros(0)} (0..2);
			}
		} # end search for offset or flex
	
    } else {	# No rodFile specified

        $rodLenFt		= $rps->{rod}{rodLenFt};
        $rodActionLenFt	= $rps->{rod}{actionLenFt};
        $numPieces	= $rps->{rod}{numPieces};
		$sectionType	= $rps->{rod}{sectionName};
		$sectionType	= substr($sectionType,10); # strip off "section - "


        my $buttDiam	= $rps->{rod}{buttDiamIn};
        my $tipDiam		= $rps->{rod}{tipDiamIn};
		
        my $buttStr		= POSIX::floor(1000*$buttDiam);
        my $tipStr		= POSIX::floor(1000*$tipDiam);
       
        $rodIdentifier = "LinearTaper_".$rodLenFt."_".$buttStr."_".$tipStr;

        $loadedRodDiamsIn = DefaultDiams($tNumRodNodes,$buttDiam,$tipDiam);
		pq($tNumRodNodes,$buttDiam,$tipDiam,$loadedRodDiamsIn);
        if ($verbose>=2){print "Diams set from default.\n"}
    }
	
    # If, after all this, there are still no thetas, use defaults:
    if (!$gotOffsets and $loadedState->isempty and $loadedThetas->isempty) {
		
		my $totalThetaRad	= eval($rps->{rod}{totalThetaDeg})*$pi/180;
        $loadedThetas = DefaultThetas($tNumRodNodes,$totalThetaRad);
        if ($verbose>=2){print "Thetas set from default.\n"}
        if (DEBUG and $verbose>=3){pq($loadedThetas)}
    }
    
    if (!$ok){print "LoadRod DETECTED ERRORS.\n"}
	
    # Coming out of here, all loadedDiams and loadedThetas reflect UNIFORM nodal spacing.  Of course, loadedState might not, but that will be dealt with later.
    return $ok;
}


# Total line (flyline, leader, tippet) variables:
my ($loadedLenFt,$loadedGrsPerFt,$loadedDiamsIn,$loadedElasticDiamsIn,$loadedElasticModsPSI,$loadedDampingDiamsIn,$loadedDampingModsPSI,
	$loadedBuoyGrsPerFt);

# Fly line specific:
my ($lineIdentifier,$flyLineNomWtGrPerFt);
my ($loadedLineLenFt,$loadedLineGrsPerFt,$loadedLineDiamsIn,
	$loadedLineElasticDiamsIn,$loadedLineDampingModsPSI);

sub LoadLine {
    my ($lineFile) = @_;
    
    ## Process lineFile if defined, otherwise set line from defaults.
    
    PrintSeparator("Loading line");
    
    my $ok = 1;
    
    $flyLineNomWtGrPerFt    = $rps->{line}{nomWtGrsPerFt};
    $loadedGrsPerFt         = zeros(0);
    
    if ($lineFile) {
        
        if ($verbose>=1){print "Data from $lineFile.\n"}
		
		my $inData;
        open INFILE, "< $lineFile" or $ok = 0;
        if (!$ok){print "ERROR: $!\n";return 0}
		{
			local $/;
        	$inData = <INFILE>;
		}
        close INFILE;
        
        if ($inData =~ m/^Identifier:\t(\S*).*\n/mo)
        {$lineIdentifier = $1; }
        if ($verbose>=2){print "lineID = $lineIdentifier\n"}
        
        $rps->{line}{identifier} = $lineIdentifier;
        
        # Find the line with "NominalWt" having the desired value;
        my ($str,$rem);
        my $ii=0;
        while ($inData =~ m/^NominalWt:\t(-?\d*)\n/mo) {
            my $tWeight = $1;
            if ($tWeight == $flyLineNomWtGrPerFt) {
                $rem = $';
                
                $loadedGrsPerFt = GetMatFromDataString($rem,"Weights");
                if ($loadedGrsPerFt->isempty){last}
                if (DEBUG and $verbose>=4){print "loadedLGrPerFt=$loadedGrsPerFt\n"}
                
                $loadedDiamsIn = GetMatFromDataString($rem,"Diameters");
                if ($loadedDiamsIn->isempty){   # Compute from estimated density:
                    my $spGrav = $rps->{line}{estimatedSpGrav};
                    my $massesPerCm = $loadedGrsPerFt*$grainsToGms/$feetToCms; # gramWts/cm.
                    my $displacements   = $massesPerCm/$waterDensity;  # cm**2;
                    my $areas			= $displacements/$spGrav;
                    $loadedDiamsIn      = sqrt($areas)/$inchesToCms;
                    #pq($spGrav,$massesPerCm,$displacements,$areas);
                }
                if (DEBUG and $verbose>=4){print "loadedLDiamsIn=$loadedDiamsIn\n"}

                last;
            }
            $inData = $';
            $ii++;
            if ($ii>15){last;}
        }
        if ($loadedGrsPerFt->isempty){$ok = 0; print "ERROR: Failed to find line weight $flyLineNomWtGrPerFt in file $lineFile.\n\n"}
        
    }else{
        
        # Create a default uniform line array.  This can have any weight:
        $lineIdentifier = "Level";
        $rps->{line}{identifier} = $lineIdentifier;
        
        $loadedGrsPerFt         = $rps->{line}{nomWtGrsPerFt}*ones(60);    # Segment wts (ie, at cg)
        $loadedDiamsIn          = $rps->{line}{nomDiameterIn}*ones(60);    # Segment diams
        
        if ($verbose>=2){print "Level line constructed from parameters.\n"}
    }
    
    $loadedElasticDiamsIn           = $rps->{line}{coreDiameterIn}*ones($loadedDiamsIn);
    $loadedElasticModsPSI           = $rps->{line}{coreElasticModulusPSI}*ones($loadedDiamsIn);
    
    $loadedDampingDiamsIn           = $loadedDiamsIn;   # Sic, at least for now.
    $loadedDampingModsPSI           = $rps->{line}{dampingModulusPSI}*ones($loadedDiamsIn);
    
    if ($verbose>=3){pq($loadedGrsPerFt,$loadedDiamsIn)}
    if (DEBUG and $verbose>=4){pq($loadedElasticDiamsIn,$loadedElasticModsPSI,$loadedDampingDiamsIn,$loadedDampingModsPSI)}
    
    return $ok;
}


# Leader variables:
my ($leaderIdentifier,$leaderStr,);
my ($leaderLenFt,$leaderElasticModPSI,$leaderDampingModPSI);

my $elasticModPSI_Nylon     = 2.1e5;
my $elasticModPSI_Fluoro    = 4e5;
my $DampingModPSI_Dummy;

sub LoadLeader {
    my ($leaderFile) = @_;
    
    ## Process leaderFile if defined, otherwise set leader from defaults.
    
    PrintSeparator("Loading leader");
    
    my $ok = 1;

    my ($leaderGrsPerFt,$leaderDiamsIn,$leaderElasticDiamsIn,$leaderElasticModsPSI,$leaderDampingDiamsIn,$leaderDampingModsPSI);
    
    my $leaderSpecGravity;

    $DampingModPSI_Dummy = $rps->{line}{dampingModulusPSI};
    print "FIX THIS: the fluoro youngs mod and both damping mods are made up by me\n";
    
    if ($leaderFile) {
        
        if ($verbose>=1){print "Data from $leaderFile.\n"}
        
        my $inData;
        open INFILE, "< $leaderFile" or $ok = 0;
        if (!$ok){print "ERROR: $!\n";return 0}
		{
			local $/;
        	$inData = <INFILE>;
		}
        close INFILE;
        
        if ($inData =~ m/^Identifier:\t(\S*).*\n/mo)
        {$leaderIdentifier = $1; }
        if ($verbose>=2){print "leaderID = $leaderIdentifier\n"}
        $leaderStr = $leaderIdentifier;
        
        $rps->{leader}{identifier} = $leaderIdentifier;
        
        # Look for the required fields:
        $leaderGrsPerFt = GetMatFromDataString($inData,"Weights");
        if ($leaderGrsPerFt->isempty){
            print "ERROR: Unable to find Weights in leader file.\n";
            return 0;
        }
        $leaderLenFt = $leaderGrsPerFt->nelem;
        #pq($leaderGrsPerFt);
        if (DEBUG and $verbose>=4){print "leaderGrPerFt=$leaderGrsPerFt\n"}
        
        $leaderDiamsIn = GetMatFromDataString($inData,"Diameters");
        if ($leaderDiamsIn->isempty){   # Compute from estimated density:
            
            if ($verbose){print "Unable to find Diameters in leader file.\n"}
            
            # Look for a Material field:
            my $materialStr = GetWordFromDataString($inData,"Material");
            if (defined($materialStr)){

                if ($verbose>=2){pq($materialStr)}
                switch ($materialStr) {
                    case "mono"     {   $leaderSpecGravity      = 1.01;
                                        $leaderElasticModPSI    = $elasticModPSI_Nylon;
                                        $leaderDampingModsPSI   = $DampingModPSI_Dummy;
                    }
                    case "fluoro"   {   $leaderSpecGravity = 1.85;
                                        $leaderElasticModPSI    = $elasticModPSI_Fluoro;
                                        $leaderDampingModsPSI   = $DampingModPSI_Dummy;
                    }
                    else {
                        print "ERROR:  Found string \"$materialStr\".  The only recognized leader materials are \"mono\" and \"fluoro\".\n";
                        return 0;
                        #$materialStr = undef;
                    }
                }
            }

            if (!defined($materialStr)){

                # Look for SpecificGravity field:
                $leaderSpecGravity = GetValueFromDataString($inData,"SpecificGravity");
                if (!defined($leaderSpecGravity)){$leaderSpecGravity = 1.1} # Presume mono.
            }
            
            # Compute diams from weights:
            if ($verbose){printf("Computing leader diameters from weights and specific gravity=%.2f (material presumed to be mono if not otherwise deducible).\n",$leaderSpecGravity)}
			
            my $massesPerCm		= $leaderGrsPerFt*$grainsToGms/$feetToCms; # gramWts/cm.
            my $displacements   = $massesPerCm/$waterDensity;  # inches**2;
            my $areas			= $displacements/$leaderSpecGravity;
            $leaderDiamsIn      = sqrt($areas)/$inchesToCms;
			#pq($weights,$displacements,$vols);
			
        } else {
            if ($leaderDiamsIn->nelem != $leaderLenFt){print "ERROR: Leader weights and diameters must have the same number of elements.\n";return 0}
        }
        
        $leaderElasticDiamsIn           = $rps->{leader}{coreDiamIn}*ones($leaderDiamsIn);
        $leaderElasticModsPSI           = $rps->{line}{coreElasticModulusPSI}*ones($leaderDiamsIn);
        
        $leaderDampingDiamsIn           = $leaderDiamsIn;   # Sic, at least for now.
        $leaderDampingModsPSI           = $rps->{line}{dampingModulusPSI}*ones($leaderDiamsIn);
        
    } else {  # Get leader from menu:
        
        $leaderStr          = $rps->{leader}{text};
        $leaderStr          = substr($leaderStr,9); # strip off "leader - "
        switch($leaderStr) {
            
            case "level"        {
                $leaderLenFt            = POSIX::floor($rps->{leader}{lenFt});
                $leaderGrsPerFt         = $rps->{leader}{wtGrsPerFt}*ones($leaderLenFt);
                $leaderDiamsIn          = $rps->{leader}{diamIn}*ones($leaderLenFt);
                
                $leaderElasticDiamsIn   = $rps->{leader}{coreDiamIn}*ones($leaderLenFt);
                $leaderElasticModPSI    = $elasticModPSI_Nylon;    # For now, at least.
                
                $leaderDampingDiamsIn   = $leaderDiamsIn;
                $leaderDampingModPSI    = $DampingModPSI_Dummy;
            }
            case "7ft 5x"       {   # mono
                $leaderLenFt            = 7;
                $leaderGrsPerFt         = pdl(0.068,0.068,0.1338,0.533,0.980,1.087,1.087);
                $leaderDiamsIn          = pdl(0.006,0.007,0.011,0.018,0.020,0.020,0.020);
                
                $leaderElasticDiamsIn   = $leaderDiamsIn;
                $leaderElasticModPSI    = $elasticModPSI_Nylon;    # For now, at least.
                
                $leaderDampingDiamsIn   = $leaderDiamsIn;
                $leaderDampingModPSI    = $DampingModPSI_Dummy;
                
            }
            case "10ft 3x"       {  # mono
                $leaderLenFt    = 10;
                $leaderGrsPerFt = pdl(0.133,0.174,0.174,0.271,0.611,1.087,1.087,1.087,1.087,1.087);
                $leaderDiamsIn  = pdl(0.008,0.009,0.010,0.011,0.013,0.016,0.018,0.019,0.020,0.020);
                
                $leaderElasticDiamsIn   = $leaderDiamsIn;
                $leaderElasticModPSI    = $elasticModPSI_Nylon;    # For now, at least.
                
                $leaderDampingDiamsIn   = $leaderDiamsIn;
                $leaderDampingModPSI    = $DampingModPSI_Dummy;
            }
            else    {die "\n\nDectected unimplemented leader text ($leaderStr).\n\nStopped"}
        }
        
        $leaderElasticModsPSI   = $leaderElasticModPSI*ones($leaderLenFt);
        $leaderDampingModsPSI   = $leaderDampingModPSI*ones($leaderLenFt);
        
    }

    if ($verbose>=3){pq($leaderGrsPerFt,$leaderDiamsIn)}
    if (DEBUG and $verbose>=4){pq($leaderElasticDiamsIn,$leaderElasticModsPSI,$leaderDampingDiamsIn,$leaderDampingModsPSI)}

    # Prepend the leader:
    $loadedLenFt += $leaderLenFt;
    
    $loadedGrsPerFt         = $leaderGrsPerFt->glue(0,$loadedGrsPerFt);
    $loadedDiamsIn          = $leaderDiamsIn->glue(0,$loadedDiamsIn);
    $loadedElasticDiamsIn   = $leaderElasticDiamsIn->glue(0,$loadedElasticDiamsIn);
    $loadedElasticModsPSI   = $leaderElasticModsPSI->glue(0,$loadedElasticModsPSI);
    $loadedDampingDiamsIn   = $leaderDampingDiamsIn->glue(0,$loadedDampingDiamsIn);
    $loadedDampingModsPSI   = $leaderDampingModsPSI->glue(0,$loadedDampingModsPSI);
    
    if ($verbose>=3){pq($leaderGrsPerFt)}
    
    return $ok;
}
        

# Tippet variables:
my ($tippetStr);
my ($tippetLenFt,$tippetElasticModPSI,$tippetDampingModPSI);

sub LoadTippet {
    
    
    # http://www.flyfishamerica.com/content/fluorocarbon-vs-nylon
    # The actual blend of polymers used to produce “nylon” varies somewhat, but the nylon formulations used to make monofilament leaders and tippets generally have a specific gravity in the range of 1.05 to 1.10, making them just slightly heavier than water. To put those numbers in perspective, tungsten—used in high-density sink tips—has a specific gravity of 19.25.
    # Fluorocarbon has a specific gravity in the range of 1.75 to 1.90. Tungsten it ain’t,
    
    # From https://www.engineeringtoolbox.com/young-modulus-d_417.html, GPa2PSI = 144,928. Youngs Mod of Nylon 6  is in the range 2-4 GPa, giving 3-6e5.   http://www.markedbyteachers.com/as-and-a-level/science/young-s-modulus-of-nylon.html puts it at 1.22 to 1.98 GPa in the region of elasticity, so say 1.5GPa = 2.1e5 PSI.  For Fluoro, see https://flyguys.net/fishing-information/still-water-fly-fishing/the-fluorocarbon-myth for other refs.
    
    PrintSeparator("Loading tippet");
    
    $tippetLenFt = POSIX::floor($rps->{tippet}{lenFt});
    my $specGravity;
    $tippetStr = $rps->{line}{text};
    $tippetStr           = substr($tippetStr,9); # strip off "tippet - "
    
    switch ($tippetStr) {
        case "mono"     {$specGravity = 1.05; $tippetElasticModPSI = $elasticModPSI_Nylon; $tippetDampingModPSI = $DampingModPSI_Dummy}
        case "fluoro"   {$specGravity = 1.85; $tippetElasticModPSI = 4e5; $tippetDampingModPSI = $DampingModPSI_Dummy;}
    }
    
    
    my $tippetDiamsIn   = $rps->{tippet}{diamIn}*ones($tippetLenFt);
    #pq($tippetLenFt,$tippetDiamsIn);
    
    my $tippetVolsPerFt           = 12*($pi/4)*$tippetDiamsIn**2;
    #pq($tippetVolsIn3);
    my $tippetGrsPerFt          =
        $tippetVolsPerFt * $specGravity * $waterDensity / $grainsToGms;
	
    my $tippetElasticDiamsIn    = $tippetDiamsIn;
    my $tippetDampingDiamsIn    = $tippetDiamsIn;
    
    my $tippetElasticModsPSI    = $tippetElasticModPSI*ones($tippetLenFt);
    my $tippetDampingModsPSI    = $tippetDampingModPSI*ones($tippetLenFt);

    if ($verbose>=2){print "Level tippet constructed from parameters.\n"}

    if ($verbose>=3){pq($tippetGrsPerFt,$tippetDiamsIn)}
    if (DEBUG and $verbose>=4){pq($tippetDiamsIn,$tippetElasticDiamsIn,$tippetElasticModsPSI,$tippetDampingDiamsIn,$tippetDampingModsPSI)}

    
    # Prepend the tippet:
    $loadedGrsPerFt         = $tippetGrsPerFt->glue(0,$loadedGrsPerFt);
    $loadedDiamsIn          = $tippetDiamsIn->glue(0,$loadedDiamsIn);
    
    $loadedLenFt += $tippetLenFt;
    
    $loadedElasticDiamsIn   = $tippetElasticDiamsIn->glue(0,$loadedElasticDiamsIn);
    $loadedElasticModsPSI   = $tippetElasticModsPSI->glue(0,$loadedElasticModsPSI);
    $loadedDampingDiamsIn   = $tippetDampingDiamsIn->glue(0,$loadedDampingDiamsIn);
    $loadedDampingModsPSI   = $tippetDampingModsPSI->glue(0,$loadedDampingModsPSI);
    
    PrintSeparator("Combining line components");
    
    if ($verbose>=3){pq($loadedGrsPerFt,$loadedDiamsIn)}
    if (DEBUG and $verbose>=4){pq($loadedElasticDiamsIn,$loadedElasticModsPSI,$loadedDampingDiamsIn,$loadedDampingModsPSI)}
}



my $driverIdentifier;
my $numDriverTimes = 21;
my $driverSmoothingFraction = 0.2;
my ($driverStartTime,$driverEndTime,$driverTs);
my ($driverXs,$driverYs,$driverZs);
my ($driverDXs,$driverDYs,$driverDZs);
my ($timeXs,$timeYs,$timeZs);  # Heirloom, used only in SetDriverFromPathSVG.

sub LoadDriver { my $verbose = 1?$verbose:0;
    my ($driverFile) = @_;
	
	## Works in inches.  Final conversion to cgs happens in SetupDriver();


    my $ok = 1;
    ## Process driverFile if defined, otherwise set directly from driver params --------

    # Unset driver pdls (to empty rather than undef):
    ($driverTs,$driverXs,$driverYs,$driverZs,$driverDXs,$driverDYs,$driverDZs) =
        map {zeros(0)} (0..6);
    ($timeXs,$timeYs,$timeZs) = map {zeros(0)} (0..2);

    # The cast drawing is expected to be in SVG.  See http://www.w3.org/TR/SVG/ for the full protocol.  SVG does 2-DIMENSIONAL drawing only! See the function SVG_matrix() below for the details.  Ditto resplines.
    
    PrintSeparator("Loading cast driver");
	
	if (NoDriverInterval()){return $ok}
		# Sets $driverStartTime,$driverEndTime, $driverXs, etc appropriately.

    if ($driverFile) {
    
        if ($verbose>=2){print "Data from $driverFile.\n"}        

       	my $inData;
        open INFILE, "< $driverFile" or $ok = 0;
        if (!$ok){print $!;goto BAD_RETURN}
		{
			local $/;
        	$inData = <INFILE>;
		}
        close INFILE;
        
        my ($name,$dir,$ext) = fileparse($driverFile,'\..*');
        $driverIdentifier = $name;
        if ($verbose>=4){pq($driverIdentifier)}
        
        if ($ext eq ".svg"){
            # Look for the "CastSplines" identifier in the file:
            #if ($inData =~ m[XPath]){
            if (0){
                if (!SetDriverFromPathSVG($inData)){$ok=0;goto BAD_RETURN};
            } else {
                if (!SetDriverFromHandleLineSegsSVG($inData)){$ok=0;goto BAD_RETURN}
                #if (!SetDriverFromHandleVectorsSVG($inData)){$ok=0;goto BAD_RETURN}
            }
        } elsif ($ext eq ".txt"){
            if (!SetDriverFromHandleTXT($inData)){$ok=0;goto BAD_RETURN};
        } else {  print "ERROR: Rod tip motion file must have .txt or .svg extension"; return 0}
		
    } else {
        if ($verbose>=2){print "No file.  Setting cast driver from params.\n"}
		SetDriverFromParams();
        $driverIdentifier = "Parameterized";
    }

	
BAD_RETURN:
    if (!$ok){print "LoadDriver DETECTED ERRORS.\n"}

    return $ok;
}


sub NoDriverInterval {

	## And if none, set the driver appropriately.

    $driverStartTime    = $rps->{driver}{startTime};
    $driverEndTime      = $rps->{driver}{endTime};
    if ($verbose>=3){pq($driverStartTime,$driverEndTime)}
    
    if ($driverStartTime >= $driverEndTime){
		# No rod tip motion.
        
     my $coordsStart = Str2Vect($rps->{driver}{powerStartCoordsIn})*12;

       ($driverXs,$driverYs,$driverZs)	= map {ones(2)*$coordsStart($_)} (0..2);
        $driverTs						= $driverStartTime + sequence(2);
			# KLUGE:  Spline interpolation requires at least 2 distinct time values.  The fact that the second time value is greater than the drive end time will not break the implementation of Calc_Driver() in Hamilton.
        return 1;
    }
	else {return 0}
}


sub SetPowerPath {
    my ($relLocs,$startCoords,$endCoords,$pivotCoords,$curvature,$skewness) = @_;
	
    ## If driver was not already read from a file, construct one here from the widget's track params:
	
	# Check that the start, end and pivot points are not co-linear:
	my $sv = $startCoords - $pivotCoords;
	my $ev = $endCoords - $pivotCoords;
	
	my $planeOK = ((($sv(1)*$ev(2)-$sv(2)*$ev(1))**2 +
		($sv(0)*$ev(2)-$sv(2)*$ev(0))**2 +
		($sv(0)*$ev(1)-$sv(1)*$ev(0))**2) != 0);
	
	# Distribute the points along a straight line first:
	my $secant	= $endCoords - $startCoords;
	my $coords = $startCoords + $relLocs->transpose*($secant);
    my $length	= sqrt(sum($secant**2));
	my $dArcs	= $length/($relLocs->nelem - 1);
	$dArcs		= $dArcs*ones($relLocs->nelem - 1);
	
	# Because of the tests applied in CheckParams(), the plane is not ok only if the start and end track points are the same:
	if (!($planeOK)){return ($coords,$dArcs,$planeOK)}
	
	# We have length and curvature, so can calculate lengths of normal offsets from secant line:
	my $locs	= $length * $relLocs;
	
	# Get vector in the plane of the track ends and the pivot that is perpendicular to the straight track and pointing away from the pivot.  Do this by projecting the pivot-to-track start vector onto the track, and subtracting that from the original vector:
	my $refVect     = $startCoords - $pivotCoords;
	my $uTrack   = $endCoords - $startCoords;
	$uTrack      /= sqrt(sum($uTrack**2));
	
	my $uNormal    = $refVect - sum($refVect*$uTrack)*$uTrack;
	$uNormal      /= sqrt(sum($uNormal**2));
	
	if ($skewness){
		# Slide the locs along the secant line:
		$locs	= SkewSequence(0,$length,$skewness,$locs);
	}
	my $dLocs	= $locs(1:-1)-$locs(0:-2);
	
	my $secantOffsets;
	$secantOffsets = ($curvature) ?
						SecantOffsets(1/$curvature,$length,$locs) :
						zeros($locs);     # Returns a flat vector.
	my $dSecantOffsets = $secantOffsets(1:-1)-$secantOffsets(0:-2);
	$dArcs	= sqrt($dLocs**2+$dSecantOffsets**2);
	
	$coords += $secantOffsets->transpose * $uNormal;
	
	return ($coords,$dArcs,$planeOK);
}


sub SetPowerTimes {
    my ($startTime,$endTime,$vMaxTime,$partialArcs) = @_;
	
	## Implements constant acceleration to vel max, then constant deceleration.
	
	my $times;
	my $ts;
	
	if ($partialArcs(-1) == 0){
		# No motion along track, so distribute times uniformly:
		
		$ts = sequence($partialArcs->nelem);
		$ts /= $ts(-1);
		$times	= $startTime + $ts*($endTime-$startTime);
		#pq($times);
		return $times;
	}
	
	# Work relatively, total time = total arc length = 1.
	my $tvMax = ($vMaxTime-$startTime)/($endTime-$startTime);

	my $acc = 2/$tvMax;
	my $dec	= 2/(1-$tvMax);
	
	#pq($tvMax,$acc,$dec);
	
	my $svMax	= 0.5*$acc*($tvMax**2);
	my $sTest	= 0.5*$dec*(1-$tvMax)**2;
	
	my $ss		= $partialArcs/$partialArcs(-1);
	
	#pq($svMax,$sTest,$ss);
	
	my $iAccs	= which($ss <= $svMax);
	my $tas		= sqrt(2*$ss($iAccs)/$acc);
	
	my $iDecs	= which($ss > $svMax);
	my $tds		= 1-sqrt(2*(1-$ss($iDecs))/$dec);
	
	#pq($iAccs,$tas,$iDecs,$tds);

	$ts		= $tas->glue(0,$tds);
	#pq($ts);
	
	$times	= $startTime + $ts*($endTime-$startTime);
	#pq($times);

	return $times;
}


sub SetPowerDirs {
    my ($coords,$pivotCoords,$startAngle,$endAngle,$angleSkewness) = @_;

	## In the usual, non-degenerate case where the start, end and pivot points are not co-linear, sets the handle direction vectors to lie in the path plane, that is, the plane defined by these points.  In that plane, the direction from the pivot to the start point is taken to be the reference direction, and all handle angles are measured relative to it.  The dirs are the vectors defined relative to the reference, with positive angles pointing toward the direction of the motion along the path. If there is no skewness, the angles are equally spaced between the parametric start and end angles, otherwise they are respaced with larger gaps later if the skewness is positive.

	## In the only allowed degenerate case, the path length is zero, the handle direction is the reference direction as in the previous paragraph, and no motion is allowed.

	my $numLocs	= $coords->dim(1);
	my $uDirs;
	#pq($numLocs);
	
	my $uRef	= $coords(:,0)-$pivotCoords;
	$uRef		/= sqrt(sum($uRef**2));
	
	my $uPerp	= undef;

	my $secant	= $coords(:,-1)-$coords(:,0);
	my $secLen	= sqrt(sum($secant**2));
	
	# If the secant length is zero, only the constant ref handle direction is allowed:
	if (!$secLen){
		$uDirs = ones($numLocs)->transpose x $uRef;
		return ($uDirs,$uRef,$uPerp);
	}
	
	# Gram-Schmidt:
	$uPerp	= $secant - sum($secant*$uRef)*$uRef;
	$uPerp	/= sqrt(sum($uPerp**2));
	
	#pq($uRef,$uPerp);
	
	my $angles =
		$startAngle + sequence($numLocs)/($numLocs-1)*($endAngle-$startAngle);
	
	if ($angleSkewness){
		$angles  = SkewSequence($startAngle,$endAngle,$angleSkewness,$angles);
	}
#	pq($angles);
	
	
	# Deflect the reference by these angles:
	$uDirs	= cos($angles)->transpose * $uRef + sin($angles)->transpose * $uPerp;
	$uDirs	/= sqrt(sumover($uDirs**2)->transpose);

	return ($uDirs,$uRef,$uPerp);
}


sub SetDriftDirs {
    my ($uRef,$uPerp,$startAngle,$endAngle,$skewness,$startFract,$stopFract,$numLocs) = @_;

	## Simulate the wrist drift at the end of the power stroke by rotating the handle directions without moving the handle top location.  This function returns  angles adjusted for slow starting and stopping as well as for skewness, expecting uniformly spaced time steps.  It turns out that this is easier to implement.
	
	## This function does not allow the degenerate case.

	my $relLocs	= sequence($numLocs+1)/($numLocs);
	
	my $tMultStart  = 1-SmoothChar($relLocs,0,$startFract);
	my $tMultStop   = SmoothChar($relLocs,1-$stopFract,1);
	
	#pq($tMultStart,$tMultStop);
	
	my $slopes  = $tMultStart*$tMultStop;
	#pq($slopes);
	
	$relLocs	= cumusumover($slopes(0:-2));
	$relLocs	/= $relLocs(-1);

	if ($skewness){
		$relLocs = SkewSequence(0,1,$skewness,$relLocs);
			# Want positive to mean fast later.
	}


	#my $numLocs	= $coords->dim(1);
	my $angles =
		$startAngle + $relLocs *($endAngle-$startAngle);
	
	#pq($relLocs,$angles);
	#Plot($relLocs,"relLocs");
	
	# Deflect the radials by these angles:
	my $uDirs = cos($angles)->transpose * $uRef + sin($angles)->transpose * $uPerp;
	$uDirs	/= sqrt(sumover($uDirs**2)->transpose);

	return $uDirs;
}


my $driverResolution = 101;
#my $driverResolution = 11;

sub SetDriverFromParams {
	
    ## If driver was not already read from a file, construct one here from the widget's track params:
	
	# At this point, still working in inches.
    my $startCoords	= Str2Vect($rps->{driver}{powerStartCoordsIn});
    my $endCoords   = Str2Vect($rps->{driver}{powerEndCoordsIn});
    my $pivotCoords = Str2Vect($rps->{driver}{powerPivotCoordsIn});
		# See CheckParams() for the restrictions it puts on these coords.
    my $length      = sqrt(sum(($endCoords - $startCoords)**2));
	
    if ($length == 0){  # No rod tip motion
        
        ($driverXs,$driverYs,$driverZs)	= map {ones(2)*$startCoords($_)} (0..2);
        $driverTs						= $driverStartTime + sequence(2);
			# KLUGE:  Spline interpolation requires at least 2 distinct time values.  The fact that the second time value is greater than the drive end time will not break the implementation of Calc_Driver() in Hamilton.
        return;
    }
	
	# First work on the power stroke ----------------
    
    my $curvature   = eval($rps->{driver}{powerCurvInvIn});
        # 1/Inches.  Positive curvature is away from the pivot.
    my $skewness	= eval($rps->{driver}{powerSkewness});

	my $startAngle	= Str2Vect($rps->{driver}{powerHandleStartDeg} * $pi/180);
	my $endAngle	= Str2Vect($rps->{driver}{powerHandleEndDeg} * $pi/180);
    my $angleSkewness	= eval($rps->{driver}{powerHandleSkewness});

	#pq($endAngle,$startAngle);

	my $uniformFracts	= sequence($driverResolution)/($driverResolution-1);
	#pq($uniformFracts);

	my ($coords,$dArcs,$planeOK)
			= SetPowerPath($uniformFracts,$startCoords,$endCoords,
							$pivotCoords,$curvature,$skewness);
	
	#pq($coords,$dArcs,$planeOK);
	
	my ($uDirs,$uRef,$uPerp)	= SetPowerDirs($coords,$pivotCoords,
							$startAngle,$endAngle,$angleSkewness);

	($driverXs,$driverYs,$driverZs)   = map {$coords($_,:)->flat} (0..2);
	#pq($driverXs,$driverYs,$driverZs);
	
	($driverDXs,$driverDYs,$driverDZs)	= map {$uDirs($_,:)->flat} (0..2);
	#pq($driverDXs,$driverDYs,$driverDZs);

    my $startTime	= $rps->{driver}{startTime};
	my $vMaxTime	= $rps->{driver}{powerVMaxTime};
    my $endTime		= $rps->{driver}{powerEndTime};

	$driverStartTime	= $startTime;
	$driverEndTime		= $endTime;

	my $partialArcs	= pdl(0)->glue(0,cumusumover($dArcs));
	my $powerTimes	= SetPowerTimes($startTime,$endTime,$vMaxTime,$partialArcs);

	$driverTs	= $powerTimes;

	# Then work on wrist drift ------------------------------
	
	if (defined($uPerp)) {
	
		$startAngle		= $endAngle;
		$endAngle		= Str2Vect($rps->{driver}{driftHandleEndDeg} * $pi/180);
		
		pq($endAngle,$startAngle);

		# For now, drift doesn't involve handle top movements, just angle change.
		my $secant	= $coords(:,-1)-$coords(:,0);
		$coords = ones($driverResolution)->transpose x $coords(:,-1);
		#pq($coords);
		my $startFract	= 0.2;
		my $stopFract	= 0.2;
		#$uDirs	= SetDriftDirs($uRef,$uPerp,$startAngle,$endAngle,$uniformFracts);
		my $velSkewness	= eval($rps->{driver}{driftVelSkewness});
		$uDirs	= SetDriftDirs($uRef,$uPerp,$startAngle,$endAngle,$velSkewness,$startFract,$stopFract,$driverResolution);

		#pq($uDirs);
		
		my ($driftXs,$driftYs,$driftZs)   = map {$coords($_,:)->flat} (0..2);
		#pq($driftXs,$driftYs,$driftZs);
		
		my ($driftDXs,$driftDYs,$driftDZs)	= map {$uDirs($_,:)->flat} (0..2);
		#pq($driftDXs,$driftDYs,$driftDZs);
		
		$driverXs = $driverXs->glue(0,$driftXs);
		$driverYs = $driverYs->glue(0,$driftYs);
		$driverZs = $driverZs->glue(0,$driftZs);
		
		$driverDXs = $driverDXs->glue(0,$driftDXs);
		$driverDYs = $driverDYs->glue(0,$driftDYs);
		$driverDZs = $driverDZs->glue(0,$driftDZs);
		
		$startTime	= sclr(Str2Vect($rps->{driver}{driftStartTime}));
		$endTime	= sclr(Str2Vect($rps->{driver}{endTime}));

		$driverEndTime	= $endTime;
			# Overwrite earlier setting.

		my $driftTs	= $startTime + $uniformFracts*($endTime-$startTime);

		#my $driftTs		= SetDriftTimes($startTime,$endTime,							$driverSmoothingFraction,$velSkewness,							$driverResolution);

		#pq($driftXs,$driftDXs,$driftTs);
		$driverTs = $driverTs->glue(0,$driftTs);
		#pq($driverTs);
	}
}



sub SetDriverFromHandleTXT {
    my ($inData) = @_;
    
    ## Blah:
    
    my $ok = 1;
    
    if ($inData =~ m/^Identifier:\t(\S*).*\n/mo)
    {$driverIdentifier = $1; }
    if ($verbose>=2){print "driverID = $driverIdentifier\n"}
	
	my $nOffsets = 0;
	
    my $xOffsets = GetMatFromDataString($inData,"XOffsets");
    if ($xOffsets->isempty){$ok = 0; print "ERROR: XOffsets not found in driver file.\n"}
	else {
		$nOffsets = $xOffsets->nelem;
		if ($nOffsets < 2){$ok=0; print "ERROR: There must me at least 2 offset in the driver file.\n"}
	}
    if (DEBUG and $verbose>=4){pq($xOffsets)}
	
    my $yOffsets = GetMatFromDataString($inData,"YOffsets");
    if ($yOffsets->isempty){$ok = 0; print "ERROR: YOffsets not found in driver file.\n"}
	elsif ($yOffsets->nelem != $nOffsets){$ok = 0; print "ERROR: YOffsets not the same size as XOffsets.\n"}
    if (DEBUG and $verbose>=4){pq($yOffsets)}
	
    my $zOffsets = GetMatFromDataString($inData,"ZOffsets");
    if ($zOffsets->isempty){$ok = 0; print "ERROR: ZOffsets not found in driver file.\n"}
	elsif ($zOffsets->nelem != $nOffsets){$ok = 0; print "ERROR: ZOffsets not the same size as XOffsets.\n"}
    if (DEBUG and $verbose>=4){pq($zOffsets)}
    
    my $xDirections = GetMatFromDataString($inData,"XDirections");
    if ($xDirections->isempty){$ok = 0; print "ERROR: XDirections not found in driver file.\n"}
	elsif ($xDirections->nelem != $nOffsets){$ok = 0; print "ERROR: ZOffsets not the same size as XOffsets.\n"}
    if (DEBUG and $verbose>=4){pq($xDirections)}
    
    my $yDirections = GetMatFromDataString($inData,"YDirections");
    if ($yDirections->isempty){$ok = 0; print "ERROR: YDirections not found in driver file.\n"}
	elsif ($yDirections->nelem != $nOffsets){$ok = 0; print "ERROR: YDirections not the same size as XOffsets.\n"}
    if (DEBUG and $verbose>=4){pq($yDirections)}
    
    my $zDirections = GetMatFromDataString($inData,"ZDirections");
    if ($zDirections->isempty){$ok = 0; print "ERROR: ZDirections not found in driver file.\n"}
	elsif ($zDirections->nelem != $nOffsets){$ok = 0; print "ERROR: ZDirections not the same size as XOffsets.\n"}
    if (DEBUG and $verbose>=4){pq($zDirections)}
	
	my $tOffsets = GetMatFromDataString($inData,"TimeOffsets");
    if ($tOffsets->isempty){
		print "WARNING: TimeOffsets not found in driver file.  Being set to a uniform sequence.\n";
		$tOffsets = sequence($xOffsets);
	}
	elsif ($tOffsets->nelem != $nOffsets){$ok = 0; print "ERROR: TimeOffsets not the same size as XOffsets.\n"}
	else {
		# Relativize times and check that they are monotonic.
		$tOffsets -= $tOffsets(0)->copy;
		$tOffsets /= $tOffsets(-1);
		my $test = $tOffsets(1:-1)-$tOffsets(0:-2);
		if (any($test<=0)){$ok=0; print "ERROR: Time offsets in file must be monotonically increasing.\n"}
	}
    if (DEBUG and $verbose>=4){pq($tOffsets)}

    if (!$ok){ return $ok}
	
    $driverXs   = $xOffsets;
    $driverYs   = $yOffsets;
    $driverZs   = $zOffsets;
	
	# If the read drivers start at (0,0,0), translate them to start at the parameterized start coords:
	if ($driverXs(0) == 0 and $driverYs(0) == 0 and $driverZs(0) == 0){
    	my $coordsStart = Str2Vect($rps->{driver}{powerStartCoordsIn});
		$driverXs += $coordsStart(0);
		$driverYs += $coordsStart(1);
		$driverZs += $coordsStart(2);
	}
	
    $driverDXs   = $xDirections;
    $driverDYs   = $yDirections;
    $driverDZs   = $zDirections;
	
	my $lens	= sqrt($driverDXs**2+$driverDYs**2+$driverDZs**2);
	$driverDXs	/= $lens;
	$driverDYs	/= $lens;
	$driverDZs	/= $lens;
	
	my $numTimes	= $driverXs->nelem;
	my $totalTime	= $driverEndTime-$driverStartTime;
	$driverTs	= $driverStartTime + $tOffsets*$totalTime;
	
    if ($verbose>=3){pq($driverTs,$driverXs,$driverYs,$driverZs,$driverDXs,$driverDYs,$driverDZs)}
	
    return $ok;
}


sub ReadNextLineGroupSVG {
    my ($inData,$thisIndex,$relativize) = @_;
    
    ## For use with SVG files produced by Adobe Illustrator.  Finds the first line group in the data string, then seeks a line object and a text object there.  If found, returns the line segment endpoints and text value.
	
	my ($x1,$y1,$x2,$y2) = map {zeros(0)} (0..4);
	my $text = "";
	
    my $label       = "";
    my $nextIndex   = -1;
	
	#pq($inData,$thisIndex);

	my $groupStr	= '';
    my $groupStart	= CORE::index($inData,"<g>",$thisIndex);
	#pq($groupStart);
	
    if ($groupStart != -1){
        my $groupEnd = CORE::index($inData,"</g>",$groupStart);
        $nextIndex = $groupEnd + 4;  #??
		#pq($nextIndex);
        if ($groupEnd != -1){
            $groupStr = substr($inData,$groupStart,$nextIndex-$groupStart+1);
        } else {
            croak "Detected unended group";
        }
	}
	#pq($groupStr);
	
	if ($groupStr ne ""){
		
		# Look for and process a line string:
        if ($groupStr =~
			m[^\s.*<line.*x1="(.*)" y1="(.*)" x2="(.*)" y2="(.*)".*/>\s.*$]m  ) {
            $x1 = $1;
            $y1 = $2;
            $x2 = $3;
            $y2 = $4;
			#pq($x1,$y1,$x2,$y2);
		}
		
		# Look for and process a text string:
        if ($groupStr =~
			m[^\s.*<text.*>(.*)</text>\s.*$]m) {
            $text = $1;
			#pq($text);
		}
	}

    return ($x1,$y1,$x2,$y2,$text,$nextIndex);
}


sub ReadNextLabeledPathSVG {
    my ($inData,$thisIndex,$relativize) = @_;
    
    ## Finds the first path in the data string, then seeks a xlink:href="# followed by the path's id.  If successful, returns the path and the linked text.  In any case, resets the data string to after the path.
    
    ## Implementing a HORRIBLE KLUGE, this function actually looks for a non-black stoke color, and if it finds one, converts the hex designator to a number, which is returned as the label.  I do this because Inkscape makes copying, moving, and releveling paths with text on them very delicate and tedius.  In contrast, setting a color (base 10, even) is quick and easy.

    my $Xs          = zeros(0);
    my $Ys          = zeros(0);
    my $label       = "";    
    my $nextIndex   = -1;

    my $pathStr = "";
    my $pathStart = CORE::index($inData,"<path\n",$thisIndex);
    if ($pathStart != -1){
        my $pathEnd = CORE::index($inData,"/>\n",$pathStart);
        $nextIndex = $pathEnd + 2;  #??
        if ($pathEnd != -1){
            $pathStr = substr($inData,$pathStart,$nextIndex-$pathStart+1);
        } else {
            die "Detected unended path";
        }
#pq $pathStr;

        # Look for the stroke designator:
        my $tStroke   = CORE::index($pathStr,"stroke:#");
        if ($tStroke != -1){
#pq $tStroke;
            my $tColor = substr($pathStr,$tStroke+8,6);
#pq $tColor;
            if ($tColor ne "000000"){
                $label = hex($tColor);
#pq $tColor;
            }
        }
        
        # If not labeled by color, look for a text label linked to the path:
        if (!$label and $pathStr =~ m[^\s.*id="(.*)"$]m) {  
            my $pathID = $1;
#pq $pathID;
            if ($pathID){
                my $linkStr = "xlink:href=\"#$pathID\"\n";
#pq $linkStr;
                
                # The text itself always seems to be after the link:
                my $tStart   = CORE::index($inData,$linkStr);
                if ($tStart != -1){
#pq $tStart;
                    my $tEnd = CORE::index($inData,"</textPath>",$tStart);
                    my $textPathStr = substr($inData,$tStart,$tEnd-$tStart+11);
#pq $textPathStr;
            
                    # A number of different forms are used to hold the label itself:
                    $label = XML_LookBefore($textPathStr,"<tspan");
#print "labelA=$label\n";
                    if (!$label){
                        $label = XML_LookBefore($textPathStr,"</tspan>");
#print "labelB=$label\n";
                        if (!$label) {
                            $label = XML_LookBefore($textPathStr,"</textPath>");
#pq $textPathStr;
#print "labelC=$label\n";
                        }
                    }
                }
            }
        }
    }
                        
    if ($label){
#pq $label;
        ($Xs,$Ys) = SVG_ExtractPathCoords($pathStr,$relativize);

    }
    
    return ($Xs,$Ys,$label,$nextIndex);
}


sub XML_LookBefore {
    my ($inStr,$markerStr) = @_;
        
    ## Seek pure text in a string before an XML marker.  Used just to make code reading easier.
    my $outStr = "";
    
    my $tEnd = CORE::index($inStr,$markerStr);
    if ($tEnd != -1) {
        my $tStart = CORE::rindex($inStr,">",$tEnd)+1;
        if ($tEnd-$tStart > 0){
            $outStr = substr($inStr,$tStart,$tEnd-$tStart);
        }
    }
    return $outStr;
}
    
        
sub SVG_ExtractPathCoords {
    my ($pathStr,$relativize) = @_;        
     
    my $Xs = zeros(0);
    my $Ys = zeros(0);

    # Look for the coordinates line:
    my ($code,$vector);
    if ($pathStr =~ m[^\s.*d="(.)\s(.*?)"$]m){
        $code    = $1;
        $vector  = $2;
#pq($code,$vector);
    }

    while ( $vector =~ m[(-?\d+?\.?\d*?),(-?\d+?\.?\d*?)(\s|$)] ){  ### broken by a x,0
#print "In while: 1=[$1],2=[$2]\n";
        $Xs = $Xs->glue(0,pdl($1));
        $Ys = $Ys->glue(0,pdl($2));
        $vector = $';
#pq $vector;
    }

#print "  After read:Xs=$Xs\nYS=$Ys\n";

    if ($code eq "m") {     # Resolve point-to-point coords:
        $Xs = cumusumover($Xs);
        $Ys = cumusumover($Ys);
    } elsif ($code ne "M"){
        die "Detected bad vector code ($code).\n";
    }

#print "  After resolve:\nXs=$Xs\nYS=$Ys\n";

    # Look for a transform to apply:
    if ($pathStr =~ m[\stransform="(\w.*?)\((.*?)\)"]) {
        if ($Xs->nelem > 2){die "transform only implented for 2 element paths.\n"}
        my $transform   = $1;
        my $content     = $2;
        ($Xs,$Ys) = SVG_ApplyTransformToSeg($transform,$content,$Xs,$Ys);
#print "  After transform:\nXs=$Xs\nYS=$Ys\n";
    }

    # Convert from matrix to window-type coords:
    $Ys = -$Ys;
    
#print "  After convert:\nXs=$Xs\nYS=$Ys\n";

    # Translate the initial point to (0,0):
    if ($relativize){
        $Xs -= $Xs(0)->sclr;
        $Ys -= $Ys(0)->sclr;
            
#print "  After translate:\nXs=$Xs\nYS=$Ys\n";
    }
    
    return($Xs,$Ys);
}



sub SetDriverFromPathSVG {
    my ($inData) = @_;
    
    ## These casts are heirloom, and take place entirely in the vertical plane.  This function depends on my very specific requirements for constructing paths from (re)splined plots.  Read the other way, it says what those conditions are.  Switched old 2D y-dim for new 3D z-dim.

#pq $inData;

    if ($verbose>=3){print "Loading cast driver from path svg...\n"}
    
    my $timeScale;
    my $valueScale;
    my $thetaMult;
	my $driverThetas;
	my $timeThetas;
    
    my $readCount = 0;
    while ($inData and $readCount < 5){
    
        my ($Xs,$Ys,$labelStr);
        ($Xs,$Ys,$labelStr,$inData) = ReadNextLabeledPathSVG($inData,1);
die "Needs work.\n";
        
#pq($readCount,$inData,$labelStr);
        
        my $ok = ($labelStr   =~ m[(\d*?)x?([A-Z]\w*)]);
        my $rem     = $';
        my $mult    = $1;
        my $label   = $2;
#pq($ok,$labelStr,$mult,$label,$rem);
    
        switch($label) {
            case "XPath"       {
               $timeXs = $Xs;
               $driverXs = $Ys;
               $readCount += 1;
            }
            case "YPath"       {
               $timeYs = $Xs;
               $driverZs = $Ys;		# sic
               $readCount += 1;
            }
            case "ThetaPath"       {
               $timeThetas = $Xs;
               $driverThetas = $Ys;
               $thetaMult = $mult;
               $readCount += 1;
            }
            case "TimeScale"       {
               my $timePx = $Xs(1)->sclr;
#pq $timePx;
               $rem =~ m[-?(\d+\.?\d*)];
               $timeScale = $1;
#pq $timeScale;
               $timeScale /= $timePx;
#pq $timeScale;
               $readCount += 1;
            }
            case "ValueScale"       {
               my $valuePx = $Ys(1)->sclr;
#pq $valuePx;
               $rem =~ m[-?(\d+\.?\d*)];
               $valueScale = $1;
#pq $valueScale;
               $valueScale /= $valuePx;
#pq $valueScale;
               $readCount += 1;
            }
        }
#print "\nreadCount(after)=$readCount\n";
    }
    
    if ($readCount < 5){die "Could not find all required paths in the SVG file.\n"}
    
    $timeXs *= $timeScale;
    $driverXs *= $valueScale;
    
    $timeYs *= $timeScale;
    $driverZs *= $valueScale;
    
    $timeThetas *= $timeScale;
    $driverThetas *= ($valueScale/$thetaMult);
	
	$driverDXs	= sin($driverThetas);
	$driverDZs	= cos($driverThetas);
		# There could be a problem here if the number of times and their values are not the same on each of the paths.
	
	$driverYs	= zeros($driverXs);
	$driverDYs	= zeros($driverXs);
    
    if ($verbose>=3){pq($timeXs,$driverXs,$timeYs,$driverYs,$timeThetas,$driverThetas)}
}



sub SetDriverFromHandleLineSegsSVG {
    my ($inData) = @_;

    ## For use with Adobe Illustrator produced plain SVG files.  These casts take place entirely in the vertical plane.  The line segs each start at the rod butt and end at the beginning of the action (just above the handle) and must be grouped with a text numerical label.  The totality of labels must be a sequential range of integers (referencing extracted frames).  Switched the 2D y's for 3D z's.

    if ($verbose>=3){print "Loading cast from handle line segments...\n"}
#pq $inData;

    my $scale;
    my $cc          = 1000;
    my $minIndex    = $cc;
    my $maxIndex    = 0;
    my $count       = 0;
	
	my ($X1s,$Y1s,$X2s,$Y2s,$labels) = map {$nan*ones($cc)} (0..4);
	
    my $thisIndex = 0;
    do {
    
        my ($x1,$y1,$x2,$y2,$text);
		
		
		($x1,$y1,$x2,$y2,$text,$thisIndex) =
					ReadNextLineGroupSVG($inData,$thisIndex);
#pq($x1,$y1,$x2,$y2,$text,$thisIndex);
        
        if ($text){
#pq($count,$inData,$text);

            if ($text =~ m[(^-?\d*?)$]) {
                my $tIndex = $text;
                if ($tIndex < $minIndex) { $minIndex = $tIndex}
                if ($tIndex > $maxIndex) { $maxIndex = $tIndex}
				
                $labels($tIndex)    .= $tIndex;
                $X1s($tIndex)		.= $x1;
                $Y1s($tIndex)		.= $y1;
                $X2s($tIndex)		.= $x2;
                $Y2s($tIndex)		.= $y2;
				
#pq($labels,$X1s,$Y1s,$X2s,$Y2s);
				
                $count += 1;
                
#pq($count,$Xs,$Ys);
#pq($handleXs,$handleYs,$handleThetas);

        
#            } elsif ($text   =~ m[^([A-Z]\w*)]) {
            } elsif ($text   =~ m[^(\w*)]) {
                my $rem     = $';
                my $label   = $1;
#pq($text,$label,$rem);

                if ($label eq "scale") {

                    # Found one:    
                    my $scaleXPx = $x2-$x1;
                    my $scaleYPx = $y2-$y1;
                    my $scalePx = sqrt($scaleXPx**2+$scaleYPx**2);       
#pq $scalePx;

                    #$rem =~ m[-?(\d+\.?\d*)];
                    $rem =~ m[(\d+\.?\d*)];
                    $scale = $1;
#pq $scale;
                    $scale /= $scalePx;
#pq $scale;
                }

           }
        }
    } while ($thisIndex >= 0);
    
    if ($count != ($maxIndex-$minIndex)+1) {
        $labels = $labels($minIndex:$maxIndex);
        print "Broken sequence (labels) = \n$labels\n";
        print "ERROR:  Detected bad label sequence in SVG.\n";
        return 0;
    }

	# Carefully, since are pdl's
    $driverXs	= $X2s($minIndex:$maxIndex)->copy;
    $driverZs	= $Y2s($minIndex:$maxIndex)->copy;			# sic
	$driverDXs	= $X2s($minIndex:$maxIndex) - $X1s($minIndex:$maxIndex);
	$driverDZs	= $Y2s($minIndex:$maxIndex) - $Y1s($minIndex:$maxIndex);	# sic
	
	#pq($driverTs,$driverXs,$driverYs,$driverZs,$driverDXs,$driverDYs,$driverDZs);
	
    if (!$scale) {print "ERROR:  Could not find \"scale\" label in SVG.\n";return 0}
    
    # Relativize to the initial handle values:
    $driverXs -= $driverXs(0)->copy;
    $driverZs -= $driverZs(0)->copy;
    
	#pq($driverXs,$driverYs,$driverZs);

    $driverXs *= $scale;
    $driverZs *= -$scale;	# sic, AI measures positive coordinates to the right and down from the ul corner of the artboard.
	
	$driverDXs *= $scale;
	$driverDZs *= -$scale;
	
	$driverYs	= zeros($driverXs);
	$driverDYs	= zeros($driverXs);
	
	#pq($driverTs,$driverXs,$driverYs,$driverZs,$driverDXs,$driverDYs,$driverDZs);

	# If the read drivers start at (0,0,0), translate them to start at the parameterized start coords:
	if ($driverXs(0) == 0 and $driverYs(0) == 0 and $driverZs(0) == 0){
    	my $coordsStart = Str2Vect($rps->{driver}{powerStartCoordsIn});		$driverXs += $coordsStart(0);
		$driverYs += $coordsStart(1);
		$driverZs += $coordsStart(2);
	}
	
	# Make direction vectors have unit length (since this is all we actually use):
	my $dirLengths = sqrt($driverDXs**2+$driverDYs**2+$driverDZs**2);
	$driverDXs /= $dirLengths;
	$driverDYs /= $dirLengths;
	$driverDZs /= $dirLengths;
	
	# There are no times in this formulation.  Set them from the params:
	if ($verbose){print "\nWARNING: There are no times specified in this type of driver file.  Driver start and stop times are set from the driver parameters!\n\n"}
	
	my $numTimes	= $driverXs->nelem;
	my $totalTime	= $driverEndTime-$driverStartTime;
	$driverTs	= $driverStartTime +
							sequence($numTimes)*$totalTime/($numTimes-1);
	
    if ($verbose>=4) {pq($driverTs,$driverXs,$driverYs,$driverZs,$driverDXs,$driverDYs,$driverDZs)}
	

    return 1;
}


sub SetDriverFromHandleVectorsSVG {
    my ($inData) = @_;

    ## These casts are heirloom, and take place entirely in the vertical plane.  The vectors each start at the rod butt and end at the beginning of the action (just above the handle).  Each vector must be a SVG 2-element path, with a numerical label in the range [0-999].  The totality of labels must be a sequential range of integers (referencing extracted frames).  Switched the 2D y's for 3D z's.

    if ($verbose>=3){print "Loading cast from handle vectors...\n"}
#pq $inData;

    my $scale;
    my $cc          = 1000;
    my $minIndex    = $cc;
    my $maxIndex    = 0;
    my $count       = 0;
    my $handleLabels    = $nan*ones($cc);
    my $handleXs        = $nan*ones($cc);
    my $handleYs        = $nan*ones($cc);
    my $handleThetas    = $nan*ones($cc);
    
    my $thisIndex = 0;
    do {
    
        my ($Xs,$Ys,$labelStr);
#pq $thisIndex;
        ($Xs,$Ys,$labelStr,$thisIndex) = ReadNextLabeledPathSVG($inData,$thisIndex);
        
        if ($labelStr){
#pq($count,$inData,$labelStr);

            if ($labelStr =~ m[(^\d*?)$]) {
                my $tIndex = $labelStr;
                if ($tIndex < $minIndex) { $minIndex = $tIndex}
                if ($tIndex > $maxIndex) { $maxIndex = $tIndex}
                
                my @aXs = $Xs->list;
                my @aYs = $Ys->list;
                my $theta = atan2($aXs[1]-$aXs[0],$aYs[1]-$aYs[0]);
                
                $handleLabels($tIndex)    .= $tIndex;
                $handleThetas($tIndex)    .= $theta;
                $handleXs($tIndex)        .= $aXs[1];
                $handleYs($tIndex)        .= $aYs[1];
                
                $count += 1;
                
#pq($count,$Xs,$Ys);
#pq($handleXs,$handleYs,$handleThetas);

        
            } elsif ($labelStr   =~ m[^([A-Z]\w*)]) {
                my $rem     = $';
                my $label   = $1;
#pq($labelStr,$label,$rem);

                if ($label eq "Scale") {

                    # Found one:    
                    my $scaleXPx = sclr($Xs(1)-$Xs(0));
                    my $scaleYPx = sclr($Ys(1)-$Ys(0));
                    my $scalePx = sqrt($scaleXPx**2+$scaleYPx**2);       
#pq $scalePx";

                    $rem =~ m[-?(\d+\.?\d*)];
                    $scale = $1;
#pq $scale;
                    $scale /= $scalePx;
#pq $scale;
                }

           }
        }
    } while ($thisIndex >= 0);
    
    if ($count != ($maxIndex-$minIndex)+1) {
        $handleLabels = $handleLabels($minIndex:$maxIndex);
        print "Broken sequence (handleLabels) = \n$handleLabels\n";
        print "ERROR:  Detected bad label sequence in SVG.\n";
        return 0;
    }

    $driverXs			= $handleXs($minIndex:$maxIndex);
    $driverZs			= $handleYs($minIndex:$maxIndex);		# sic
    my $driverThetas	= $handleThetas($minIndex:$maxIndex);
	$driverDXs			= sin($driverThetas);
	$driverDZs			= cos($driverThetas);
    
    if (!$scale) {print "ERROR:  Could not find \"Scale\" label in SVG.\n";return 0}
    
    # Relativize to the initial handle values:
    $driverXs -= $driverXs(0)->sclr;
    $driverZs -= $driverZs(0)->sclr;
    
    $driverXs *= $scale;
    $driverZs *= $scale;
	
	$driverYs	= zeros($driverXs);
	$driverDYs	= zeros($driverXs);
	
	# If the read drivers start at (0,0,0), translate then to start at the parameterized start coords:
	if ($driverXs(0) == 0 and $driverYs(0) == 0 and $driverZs(0) == 0){
    	my $coordsStart = Str2Vect($rps->{driver}{powerStartCoordsIn});
		$driverXs += $coordsStart(0);
		$driverYs += $coordsStart(1);
		$driverZs += $coordsStart(2);
	}
	
	# Make direction vectors have unit length (since this is all we actually use):
	my $dirLengths = sqrt($driverDXs**2+$driverDYs**2+$driverDZs**2);
	$driverDXs /= $dirLengths;
	$driverDYs /= $dirLengths;
	$driverDZs /= $dirLengths;
	
	# There are no times in this formulation.  Set them from the params:
	if ($verbose){print "\nWARNING: There are no times specified in this type of driver file.  Driver start and stop times are set from the driver parameters!\n\n"}
	my $numTimes	= $driverXs->nelem;
	my $totalTime	= $driverEndTime-$driverStartTime;
	$driverTs	= $driverStartTime +
							sequence($numTimes)*$totalTime/($numTimes-1);

    if ($verbose>=3) {pq($driverTs,$driverXs,$driverYs,$driverZs,$driverDXs,$driverDYs,$driverDZs)}

    return 1;
}



# Variables loaded by SetupModel():
my $nominalG;
my ($rodLen,$rodActionLen,$handleLen);
my $numRodNodes;
my ($numRodSegs,$rodSegLens,$rodSegDiams,$rodSegMasses,$rodBendKs,$rodBendCs);
my ($numLineSegs,$lineSegLens,$lineSegDiams,$lineSegMasses,$lineSegKs,$lineSegCs);
my ($flyNomLen,$flyNomDiam,$flyMass);
my ($loopActiveLenFt,$loopActiveLen);   # Total loop length, outside of rod tip, including leader and tippet.

my ($numSegs,$segLens,$segDiams,$segMasses,$segKs,$segCs);
my ($outStr,$paramsStr);

my ($lineTipOffset,$leaderTipOffset);


sub SetupModel { my $verbose = 1?$verbose:0;

    ## Called just prior to running. Convert the rod and line file data to a specific model for use by the integrator.  Note that this function does not deal with initial rod or line configuration, but just with its physical properties.
	
	## In the present model, the segment masses are located at the outboard segment node.  The last outboard line segment mass is the sum
	
	## This is where most conversion to CGS (used by Hamilton) is done.
    
    PrintSeparator("Setting up model (Units are CGS)");

    # Deal with parameters that need units conversion or for which it is convenient to have renamed globals:
    $nominalG  = $rps->{ambient}{nominalG};
    
    # Setup rod -----------------------

    # See if state, and then, necessarily, rod and line segs, were loaded:
    if ($loadedState->isempty){

        $numRodSegs     = $rps->{rod}{numSegs};
        $numRodNodes    = $numRodSegs+1;
        $rodSegLens     = zeros(0);

        $numLineSegs    = $rps->{line}{numSegs};
        $lineSegLens	= zeros(0);

    } else{

		$numRodSegs     		= $loadedRodSegLens->nelem;
        $numRodNodes    		= $numRodSegs+1;
        $rps->{rod}{numSegs}	= $numRodSegs;   # Show the user.
        $rodSegLens     		= $loadedRodSegLens;

        $numLineSegs   			= $loadedLineSegLens->nelem;
        $rps->{line}{numSegs}	= $numLineSegs;   # Show the user.
        $lineSegLens			= $loadedLineSegLens;
    }
    
	my ($rodSegMasses,$rodSegDiams,$rodStretchKs,$rodStretchCs)
			= map {zeros(0)} (0..3);
			# Make sure there is something to glue the line to if no rod segs.
	($rodBendKs,$rodBendCs) = map {zeros(0)} (0..1);
	
	#pq($rodSegMasses,$rodSegCGs,$rodSegDiams,$rodStretchKs,$rodStretchCs,$rodBendKs,$rodBendCs);die;
	
    my ($totalRodActionWtOz);
    $numSegs = $numRodSegs + $numLineSegs;

    if ($numRodSegs){
		
        # Convert to CGS where necessary:
        $rodLen			= $rodLenFt * $feetToCms;
        $rodActionLen	= $rodActionLenFt * $feetToCms;
        $handleLen		= $rodLen - $rodActionLen;
		if ($verbose>=2){pq($rodLen,$rodActionLen,$handleLen)}
		
        my $rodDensity          = $rps->{rod}{densityLbFt3} * $lbsPerFt3ToGmsPerCm3;
        my $rodElasticModulus   = $rps->{rod}{elasticModulusPSI} * $psiToDynesPerCm2;
        my $rodDampModStretch	= $rps->{rod}{dampingModulusStretchPSI} * $psiToDynesPerCm2;
        my $rodDampModBend		= $rps->{rod}{dampingModulusBendPSI} * $psiToDynesPerCm2;
		
print "WARNING: units for damp mods should be multiplied by secs.\n";

        my $zeroFiberThickness	= $rps->{rod}{zeroFiberThicknessIn} * $inchesToCms;
        my $fiberGradient       = ($zeroFiberThickness) ? 1/$zeroFiberThickness : 0;
        my $maxWallThickness    = $rps->{rod}{maxWallThicknessIn} * $inchesToCms;
        my $ferruleKsMult       = $rps->{rod}{ferruleKsMult};
        my $vAndGMultiplier     = $rps->{rod}{vAndGMultiplier};

		if ($verbose>=3){
			pq($rodDensity,$fiberGradient,$maxWallThickness,$ferruleKsMult,$vAndGMultiplier);
			
			#pqf("%5.1f ",$rodElasticModulus,$rodDampModStretch,$rodDampModBend);
			printf("\$psiToDynesPerCm2 = %5.3e\n\$rodElasticModulus = %5.3e\n\$rodDampModStretch = %5.3e\n\$rodDampModBend = %5.3e\n",$psiToDynesPerCm2,$rodElasticModulus,$rodDampModStretch,$rodDampModBend);
		}

        
        #if (!$rodSegLens->isempty){
        if ($rodSegLens->isempty){ # Otherwise all this was loaded.

            # Set up the rod segment lengths.  These are in inches:
            my $nodeLocs = sequence($numRodSegs+1)**$rps->{rod}{segExponent};

            $nodeLocs *= $rodActionLen/$nodeLocs(-1);
            if ($verbose>=1){print "rodNodeLocs=$nodeLocs\n"}
            
            $rodSegLens = $nodeLocs(1:-1)-$nodeLocs(0:-2); # Cms here.
            $rodSegLens = $rodSegLens(-1:0);
                # Want the short segments at the tip.
        }

        if ($verbose>=2){pq $rodSegLens}
        
        my $nodeFractLocs = cumusumover(zeros(1)->glue(0,$rodSegLens));
        $nodeFractLocs /= $nodeFractLocs(-1);
        if ($verbose>=3){pq $nodeFractLocs}
           
        my $rodNodeDiams =
			ResampleVectLin($loadedRodDiamsIn*$inchesToCms,$nodeFractLocs);
        if ($verbose>=2){pq $rodNodeDiams}
        
        # Figure effective nodal diam second moments (adjusted for power fiber distribution).  Uses the diameter at the segment lower end:
		#pq($maxWallThickness);
		
		# To remain consistent with previous work where the rod dynamical variables were angles, we make rod bend K's and C's that are torques.  They will be converted into forces (which we need for our current cartesian dynamical variables) in Calc_pDotsRodMaterial().
 
        my ($effectiveSectAreas,$effectiveSect2ndMoments) =
			GradedFiberMoments($sectionType,$rodNodeDiams(0:-2),$fiberGradient,$maxWallThickness);	# Uses inboard node diams.
        if ($verbose>=3){pq($effectiveSectAreas,$effectiveSect2ndMoments)}

		#  Compute hinge spring torques (adjusted for additional ferrule stiffness).  Need to know the seg lens to deal with the ferrules.
		$rodBendKs = RodKs($rodSegLens,$effectiveSect2ndMoments,$rodElasticModulus,
                            $ferruleKsMult,$handleLen,$numPieces);
			# Includes division by $segLens.
		pq($rodBendKs);

        # Use the same second moments as for K's:
         $rodBendCs = ($rodDampModBend/$rodElasticModulus)*$rodBendKs;
        # Presumes that internal friction arises from power fiber configuration in the same way that bending elasticity does.  The relative local bits of motion cause a local drag tension (compression), but the ultimate force on the mass is just the same as the local ones (all equal if uniform velocity strain. I have no independent information about the appropriate value for the damping modulus.  Running the simulation, small values lead to complete distruction of the rod.  Values nearly equal to the elastic modulus give seemingly appropriate rod tip damping.  For the moment, I'll let the dampingModulus eat any constant factors.
        if ($verbose>=3){pq( $rodBendKs,$rodBendCs)}

        $rodSegDiams = $rodNodeDiams(1:-1);	# Outboard node diams.
        if ($verbose>=3){pq($rodSegDiams)}

        # When stretching, just the diameter counts, and the average segment diameter ought to be better than the lower end diameter.  However, for now, I'll use the node fiber counts to stay consistent with what I did for bending:
		
        $rodStretchKs = $rodElasticModulus*$effectiveSectAreas/$rodSegLens;
        $rodStretchCs = $rodDampModStretch*$effectiveSectAreas/$rodSegLens;
		if ($verbose>=3){pq($rodStretchKs,$rodStretchCs)}

        # Figure segment masses:
        my ($segBlankMasses,$unused) =
            RodSegMasses($sectionType,$rodSegLens,$rodNodeDiams,$rodDensity,
                            $fiberGradient,$maxWallThickness);
		

        my $flyLineNomMassPerCm   = $flyLineNomWtGrPerFt*$grainsToGms/$feetToCms;
        
        my ($segExtraMasses,$segExtraMoments) =
            RodSegExtraMasses($sectionType,$rodSegLens,$rodNodeDiams,$vAndGMultiplier,$flyLineNomMassPerCm,$handleLen,$numPieces);
        
        $rodSegMasses	= $segBlankMasses + $segExtraMasses;
		
        $totalRodActionWtOz = sum($rodSegMasses)/$ouncesToGms;
    }


    # Setup line --------------------
    
    my ($totalLineLoopMass,$totalLineLoopWtOz);
	
    if ($numLineSegs) {
        
        $paramsStr .= "Line: $lineIdentifier\n";
		
		# For compatibility with the user interface, it is easiest to work with lengths in feet until the very end.

        my $lineLenFt   = $rps->{line}{activeLenFt};
        if ($verbose>=3){pq($lineLenFt,$leaderLenFt,$tippetLenFt)}
		
        $loopActiveLenFt = $lineLenFt + $leaderLenFt + $tippetLenFt;
		my $loopActiveLen = $loopActiveLenFt * $feetToCms;
        if ($verbose>=3){pq($loopActiveLenFt,$loopActiveLen)}
		
		# These next used in Run(), so ok to convert:
        $leaderTipOffset    = $tippetLenFt*$feetToCms;
        $lineTipOffset      = $leaderTipOffset + $leaderLenFt*$feetToCms;
        pq($lineTipOffset,$leaderTipOffset);
		
		# Figure the segment weights -------

		# Take just the active part of the line, leader, tippet.  Low index is TIP:
		my $lastFt  = POSIX::floor($loopActiveLenFt);
		#pq ($lastFt,$totalActiveLenFt,$loadedGrsPerFt);
		
		my $availFt = $loadedGrsPerFt->nelem;
		if ($lastFt >= $availFt){confess "\nERROR:  Active length (sum of line outside rod tip, leader, and tippet) requires more fly line than is available in file.  Set shorter active len or load a different line file.\nStopped"}
		
		my $activeLineGrs   =  $loadedGrsPerFt($lastFt:0)->copy;    # Re-index to start at rod tip.
		if ($verbose>=3){pq($activeLineGrs)}
		
        my $fractNodeLocs;
        if ($lineSegLens->isempty) {
            $fractNodeLocs = sequence($numLineSegs+1)**$rps->{line}{segExponent};
        } else {
            $fractNodeLocs = cumusumover(zeros(1)->glue(0,$lineSegLens));
        }
        $fractNodeLocs /= $fractNodeLocs(-1);
       
        my $nodeLocs	= $loopActiveLenFt * $fractNodeLocs * $feetToCms;
        if ($verbose>=3){pq($fractNodeLocs,$nodeLocs)} 	# Cms
        
		# Figure the seg lengths.
		$lineSegLens	= $nodeLocs(1:-1)-$nodeLocs(0:-2);
        if ($verbose>=3){pq($lineSegLens)}		# Cms

		my $lineSegGrs = SegShares($activeLineGrs,$nodeLocs);
			# This works with $nodeLocs in cms because of the way SegShares() was defined.
		
		$lineSegMasses = $lineSegGrs*$grainsToGms;
		if ($verbose>=3){pq($lineSegGrs,$lineSegMasses)}
		
		$totalLineLoopWtOz = sum($lineSegMasses)/$ouncesToGms;


        my $activeDiamsIn =  $loadedDiamsIn($lastFt:0)->copy;
			# Re-index to start at rod tip.
		
		if (DEBUG and $verbose>=4){pq($activeDiamsIn)}
		
        $lineSegDiams = ResampleVectLin($activeDiamsIn,$fractNodeLocs(1:-1)) * $inchesToCms;	# Our convention is diameter at outboard node, where the mass is nominally concentrated.
        if ($verbose>=3){pq($lineSegDiams)}
		
		
        # Compute Ks and Cs based on the diams at the inboard nodes:
		my $activeElasticDiamsIn	=  $loadedElasticDiamsIn($lastFt:0)->copy;
		my $activeElasticModsPSI	=  $loadedElasticModsPSI($lastFt:0)->copy;
		my $activeDampingDiamsIn	=  $loadedDampingDiamsIn($lastFt:0)->copy;
		my $activeDampingModsPSI	=  $loadedDampingModsPSI($lastFt:0)->copy;
		
		my $fractInboardNodeLocs	= $fractNodeLocs(0:-2);

        my $nodeElasticDiams
			= ResampleVectLin($activeElasticDiamsIn,$fractInboardNodeLocs) * $inchesToCms;
        my $nodeElasticMods
			= ResampleVectLin($activeElasticModsPSI,$fractInboardNodeLocs) * $psiToDynesPerCm2;
		
        my $nodeDampingDiams
			= ResampleVectLin($activeDampingDiamsIn,$fractInboardNodeLocs) * $inchesToCms;
 
		my $nodeDampingMods
			= ResampleVectLin($activeDampingModsPSI,$fractInboardNodeLocs) * $psiToDynesPerCm2;
		
        if ($verbose>=3){pq($nodeElasticDiams,$nodeElasticMods,$nodeDampingDiams,$nodeDampingMods)}
    
        # Build the active Ks and Cs:
        my $nodeElasticAreas    = ($pi/4)*$nodeElasticDiams**2;
        $lineSegKs = $nodeElasticMods*$nodeElasticAreas/$lineSegLens; # dynes to stretch 1 cm. ??
        # Basic Hook's law, on just the level core, which contributes most of the stretch resistance.
        
        my $nodeDampingAreas    = ($pi/4)*$nodeDampingDiams**2;
        $lineSegCs = $nodeDampingMods*$nodeDampingAreas/$lineSegLens; # Dynes to stretch 1 cm.
        # By analogy with Hook's law, on the whole diameter. Figure the elongation damping coefficients USING FULL LINE DIAMETER since the plastic coating probably contributes significantly to the stretching friction.
        
        if ($verbose>=3){pq($lineSegKs,$lineSegCs)}
    }
    
    # Set the fly specs:
    $flyMass		= eval($rps->{fly}{wtGr}) * $grainsToGms;
    $flyNomLen      = eval($rps->{fly}{nomLenIn})* $inchesToCms;
    $flyNomDiam     = eval($rps->{fly}{nomDiamIn})* $inchesToCms;
    if ($verbose>=3){pq($flyMass,$flyNomLen,$flyNomDiam)}
	
	
    # Combine rod and line (including leader and tippet) and fly:
    $segMasses	= $rodSegMasses->glue(0,$lineSegMasses)->glue(0,pdl(0));
		# Fly mass will be added in Hamilton.
	$segMasses	= 0.5*($segMasses(0:-2)+$segMasses(1:-1));
		# We will treat the mass as if it is located at the outboard node of the segment and has the average value of the preceeding and following segs.

    $segDiams	= $rodSegDiams->glue(0,$lineSegDiams);
    $segLens    = $rodSegLens->glue(0,$lineSegLens);
	
    $segKs      = $rodStretchKs->glue(0,$lineSegKs);
    $segCs      = $rodStretchCs->glue(0,$lineSegCs);
	pq($segMasses,$segDiams,$segLens,$segKs,$segCs);

    if ($verbose>=2){
		print "\n";
		if ($numRodSegs){pq($totalRodActionWtOz)}
		if ($numLineSegs){pq($totalLineLoopWtOz)}
		print "\n"
	}
    
}



my ($driverXSpline,$driverYSpline,$driverZSpline,
    $driverDXSpline,$driverDYSpline,$driverDZSpline,
    $frameRate,$driverTotalTime,
    $tipReleaseStartTime,$tipReleaseEndTime,
    $integrationStr);

sub SetupDriver { my $verbose = 1?$verbose:0;

    ## Prepare the external constraint at the handle that is applied during integration by Calc_Driver() in RHamilton3D.
    
	
    PrintSeparator("Setting up handle driver");

    #pq($timeXs,$timeYs,$timeZs);
	if ($timeXs->isempty){
		($timeXs,$timeYs,$timeZs) = map {$driverTs} (0..2);
	} else {
		my $tStarts = $timeXs(0)->glue(0,$timeYs(0))->glue(0,$timeZs(0));
		$driverStartTime = $tStarts->max;
		my $tEnds =
			$timeXs(-1)->glue(0,$timeYs(-1))->glue(0,$timeZs(-1));
			# If they came from resplining, they might be a tiny bit different.
		$driverEndTime = sclr($tEnds->min);
	}
	
	if (DEBUG and $rps->{driver}{showTrackPlot}){
        my %opts = (gnuplot=>$gnuplot,xlabel=>"x-axis(in)",ylabel=>"y-axis(in)",zlabel=>"z-axis(in)");
        Plot3D($driverXs,$driverYs,$driverZs,"Raw Handle Top Track (in)",\%opts);

		%opts = (gnuplot=>$gnuplot,xlabel=>"x-direction",ylabel=>"y-direction",zlabel=>"z-direction");
		Plot3D($driverDXs,$driverDYs,$driverDZs,"Toward handle top",pdl(0),pdl(0),pdl(0),"Handle bottom","Raw Handle Directions Track (dimensionless)",\%opts);
    }

	#pq($driverXs,$driverYs,$driverZs);
	#pq($driverDXs,$driverDYs,$driverDZs);
	#pq($timeXs,$timeYs,$timeZs);
	#sleep(5);

	
    $driverTotalTime = $driverEndTime-$driverStartTime;        # Used globally.
    if ($verbose>=3){pq $driverTotalTime}

    # Interpolate in arrays, all I have for now:
    my @aTimeXs     = list($timeXs);
    my @aTimeYs     = list($timeYs);
    my @aTimeZs     = list($timeZs);
	
    my @aDriverXs = list($driverXs * $inchesToCms);
    my @aDriverYs = list($driverYs * $inchesToCms);
    my @aDriverZs = list($driverZs * $inchesToCms);
    
    my @aDriverDXs = list($driverDXs);	# Dimensionless.
	## ?? But check if we take derivatives? and how they are used...
    my @aDriverDYs = list($driverDYs);
    my @aDriverDZs = list($driverDZs);
    
    $driverXSpline = Math::Spline->new(\@aTimeXs,\@aDriverXs);
    $driverYSpline = Math::Spline->new(\@aTimeYs,\@aDriverYs);
    $driverZSpline = Math::Spline->new(\@aTimeZs,\@aDriverZs);
    
    $driverDXSpline = Math::Spline->new(\@aTimeXs,\@aDriverDXs);
    $driverDYSpline = Math::Spline->new(\@aTimeYs,\@aDriverDYs);
    $driverDZSpline = Math::Spline->new(\@aTimeZs,\@aDriverDZs);

   if ($rps->{driver}{showTrackPlot}){
        my $numTs = 30;	# Not so many that we can't see the velocity differences.
        PlotHandleSplines($numTs,$driverXSpline,$driverYSpline,$driverZSpline,
        $driverDXSpline,$driverDYSpline,$driverDZSpline,1);  # Plot 3D.
    }

    # Plot the cast with enough points in each segment to show the spline behavior:
   #if (DEBUG and $rps->{driver}{showTrackPlot}){
   if (0 and $rps->{driver}{showTrackPlot}){
        my $numTs = 100;
        PlotHandleSplines($numTs,$driverXSpline,$driverYSpline,$driverZSpline,
        $driverDXSpline,$driverDYSpline,$driverDZSpline);  # To terminal only.
    }

	# All integration control times were rationalized by CheckParams():
    my $releaseDelay        = $rps->{holding}{releaseDelay};
    my $releaseDuration     = $rps->{holding}{releaseDuration};
    my $driverStartTime		= $rps->{driver}{startTime};
    my $t0					= $rps->{integration}{t0};
	
    if ($releaseDelay < 0) {
        # Turn off delay mechanism.  So no holding:
        $tipReleaseStartTime    = $t0 - 1;
        $tipReleaseEndTime      = $t0 - 0.5;
    } else {
        $tipReleaseStartTime    = $driverStartTime + $releaseDelay;
        $tipReleaseEndTime      = $tipReleaseStartTime + $releaseDuration;
    }
   
    # Set driver string:    
    my $tRel = sprintf("%.3f,%.3f",
					$tipReleaseStartTime,
					$tipReleaseEndTime);
    my $tTRS = sprintf("%.3f",$tipReleaseStartTime);
    my $tTRE = sprintf("%.3f",$tipReleaseEndTime);
	my $tInt = sprintf("%.3f:%.3f:%.3f",
				$rps->{integration}{t0},
				$rps->{integration}{t1},
				$rps->{integration}{plotDt});
	
    $integrationStr =  "INTEGRATION: t=($tInt); stepper=$rps->{integration}{stepperName}; Release(s,e,K,C)=($tRel,$rps->{holding}{springConstOzPerIn},$rps->{holding}{dampingConstOzSecPerIn})";

    #if ($verbose>=2){pq $integrationStr}
	
}




my ($eventTs,$iEvents);

# In the current implementation, there need be no events.  However, for now I keep them for their side effects on $holding.  They never trigger a change in the number of line segments.
sub SetEventTs { my $verbose = 1?$verbose:0;
    my ($t0,$tipReleaseStartTime,$tipReleaseEndTime) = @_;

    ## Set the times of the scheduled, typically irregular, events that mark a change in integrator behavior.
    
    # In the current implementation, hold, if any, must start at T0.
    #pq($t0,$tipReleaseStartTime,$tipReleaseEndTime);
	
    if ($tipReleaseEndTime <= $t0) # Our indication that there is no holding.
                {$eventTs = zeros(0)}    # No hold required.
    elsif ($tipReleaseStartTime<=$tipReleaseEndTime){
        
        $eventTs      = pdl($tipReleaseStartTime)->glue(0,pdl($tipReleaseEndTime));
    }
    else {die "ERROR:  Detected incompatible hold times.\n"}
    
    if ($verbose>=3){pq($eventTs)}
    
    return $eventTs;
}


sub PlanarAnglesToOffsets {
    my ($axialAngle,$theta0,$relThetas,$segLens) = @_;
	
	## Think right-handed x,y,z.  $theta0 = 0 points along the poistive z-axis, and increasing moves toward positve x.  $axialA = 0 points along the positive z-axis, and increasing moves toward positive y.  After figuring the offsets in the x-z plane, rotates around the x-axis.

	my $thetas	= cumusumover($relThetas)+$theta0;
	my $dxs		= $segLens * sin($thetas);
	my $dzs		= $segLens * cos($thetas);

	my $dys		= $dzs * sin($axialAngle);
	$dzs		*= cos($axialAngle);
	
	return ($dxs,$dys,$dzs);
}



sub SetRodStartingConfig {
    my ($segLens) = @_;
	
	# Driver dirs have been loaded by this time.
	
	my ($rodDxs0,$rodDys0,$rodDzs0);
	#pq($dXs,$dYs,$dZs,$loadedThetas);
	
	# See if we have 3D offset data:
	if ($loadedThetas->isempty and !($dXs->isempty or $dYs->isempty or $dXs->isempty)){
		# In this case, we have $dYs and $dZs as well, and nothing to do, since I presume the offsets were recorded from the same picture that gave the original handle direction.  This might want to be rethought.
		
	### Assume handle butt is included as (0,0,0).  We don't put it in the output of this function, but maybe should use it to initialize driver direction?  For the moment I just throw it away.  Assume the loaded data have arbitrary scale.
		
		## Need to resample appropriately.
		my $rodNodeRelLocs = cumusumover(zeros(1)->glue(0,$rodSegLens));
        $rodNodeRelLocs /= $rodNodeRelLocs(-1);    
        if (DEBUG and $verbose>=3){pq $rodNodeRelLocs}
		
		# Remove handle offsets:
		$dXs = $dXs(1:-1);
		$dYs = $dYs(1:-1);
		$dZs = $dZs(1:-1);

		# Adjust length:
		my $dRs		= sqrt($dXs**2 + $dYs**2 + $dZs**2);
		my $tLen	= sum($dRs);
		
		my $mult = $rodActionLen/$tLen;
		$dXs *= $mult;
		$dYs *= $mult;
		$dZs *= $mult;
		
		# Integrate the dXs, etc:
		my $Xs = cumusumover($dXs);
		my $Ys = cumusumover($dYs);
		my $Zs = cumusumover($dZs);
		
		
        $Xs = ResampleVectLin($Xs,$rodNodeRelLocs);
        $Ys = ResampleVectLin($Ys,$rodNodeRelLocs);
        $Zs = ResampleVectLin($Zs,$rodNodeRelLocs);

		$rodDxs0 = $Xs(1:-1)-$Xs(0:-2);
		$rodDys0 = $Ys(1:-1)-$Ys(0:-2);
		$rodDzs0 = $Zs(1:-1)-$Zs(0:-2);
		
	} elsif (!$loadedThetas->isempty) {
	
		## Set up the rod based on the initial handle direction.  It will lie in the plane defined by the x-axis and that direction unless they are parallel.  In that case the rod will taken to lie in the vertical plane.

		my $relThetas = ResampleThetas($loadedThetas,$rodSegLens);
			# This  call involves a spline, so returns may not be just what we expect.
		$relThetas = $relThetas(0:-2);	# Get rid of the extra zero.  But also should do better interpolation.
		#pq($loadedThetas);
		#pq($rodSegLens);
		#pq($relThetas);
		
		my $lineTheta0Deg  = eval($rps->{line}{angle0Deg});  # To set rod convexity direction.
		#pq($lineTheta0Deg);

		# Set rod convexity from line initial direction:
		if ($lineTheta0Deg <= 0){$relThetas *= -1}
		
		if ($verbose>=3){pq $relThetas}

		# Driving plane rotation about x direction:
		my $axialAngle	= ($driverDYs(0) == 0) ? 0 : atan2($driverDYs(0),$driverDZs(0));
			# Measured relative to the z-axis;
		
		# Initial handle angle in the vertical plane:
		my $theta0		= atan2($driverDXs(0),$driverDZs(0));
			# Measured relative to the z-axis.
		
		#pq($segLens);
		#pq($axialAngle,$theta0);

		($rodDxs0,$rodDys0,$rodDzs0) =
			PlanarAnglesToOffsets($axialAngle,$theta0,$relThetas,$segLens);
		
	} else {
		die "ERROR: Could not find rod initial configuration data.\nStopped";
	}

	if ($verbose>=3){pq($rodDxs0,$rodDys0,$rodDzs0)}

	return ($rodDxs0,$rodDys0,$rodDzs0);
}



sub SetLineStartingConfig {
    my ($lineSegLens) = @_;
    
    ## Take the initial line configuration as straight and horizontal, deflected from straight downstream by the specified angle (pos is toward the plus Y-direction).
    PrintSeparator("Setting up starting line configuration");

    my $linePreTension		= eval($rps->{line}{preTensionOz}) * $ouncesToDynes;
	my $linePreStretches	= $linePreTension/$lineSegKs;
	my $adjustedLineSegLens	= $lineSegLens+$linePreStretches;
	pq($lineSegLens,$linePreStretches,$adjustedLineSegLens);

    my $lineTheta0  = eval($rps->{line}{angle0Deg})*$pi/180;
    my $lineCurve0  = eval($rps->{line}{curve0InvFt})/$feetToCms;    # 1/cm
    
    #if ($lineTheta0 < 0){$lineCurve0 *= -1}
    
    #$lineTheta0 += $pi/2;
    my ($dzs0,$dxs0) = RelocateOnArc($adjustedLineSegLens,$lineCurve0,$lineTheta0);
	
	# For testing radius of curvature against tension and gravitational deflection):
	if (abs(eval($rps->{line}{angle0Deg})) == 90){
		my $origLen		= sum($lineSegLens);
		my $stretchLen	= sum($adjustedLineSegLens);
		pq($linePreTension,$origLen,$stretchLen);
		
		my $zs0 = cumusumover(pdl(0)->glue(0,$dzs0));
		pq($zs0);	}
    
    my $dys0 = zeros($dxs0);
    #if ($verbose>=3){pq($dxs0,$dys0,$dzs0)}
    
    if (DEBUG and $verbose>=4){pq($lineTheta0)}
    
    return ($dxs0,$dys0,$dzs0);
}




my ($dragSpecsNormal,$dragSpecsAxial,$segAirMultRand);
my ($rodLineStr,$driverAmbientStr);
my ($timeStr,$lineStr);
my ($T0,$Dynams0,$dT0,$dTPlot);
my $numNodes;
my %opts_plot;
my $holding;		# Currently unused.
my ($T,$Dynams);
	# Will hold the complete integration record.  I put them up here since $T will be undef'd in SetupIntegration() as a way of indicating that the CastRun() initialization has not yet been done.

sub SetupIntegration { my $verbose = 1?$verbose:0;
    
    ## Initialize PDLs that used during the integration, importantly including those that will be held constant.
    
    # Note that most physical values are are calculated for the inertial nodes.  However, I find air drag is most easily computed at the rod and line segment midpoints, and the resulting forces redistributed to the nodes.  Thus,
    
    PrintSeparator("Setting up integration pdls");
    
    #print("\n\nWORRY about whether the frictional terms belong in KE or PE.\n\n");
	
    $numNodes = 1 + $numRodNodes + $numLineSegs;   # Starts with the handle bottom node, which $numRodNodes does not.
    if ($numNodes<3){die "There must be at least 3 nodes total.\n"}
	
    if (any($segMasses) <= 0){die "Segment masses must be positive.\n"}
	
    PrintSeparator("Setting up fluid friction");
    
    # Air friction contributes damping to both the rod and the line.  I use the real air friction coeff, and appropriately modelled form factors.  In any case, the drag coeffs should be proportional to section surface area.  Eventually I might want to acknowledge that the flows around the rod's hex section and the lines round section are different.  See below and Calc_FluidDrags() for the details.
    
    # Setup drag for the line segments:
    $dragSpecsNormal    = Str2Vect($rps->{ambient}{dragSpecsNormal});
    $dragSpecsAxial     = Str2Vect($rps->{ambient}{dragSpecsAxial});
    
    
        # For slack line segments, I want to adjust the standard drag formula with a strain-weighted contribution computed as if the line were locally oriented in a completely random direction.  My formula for the drag multiplier in this case, assuming for simplicity only a v^2 dependence is F = (4/3pi)*rho*L*D*(C1A+C1N)*V^2:

    $segAirMultRand = 0;
    print "REMINDER:  Fix segAirMultRand.\n";
=begin comment

OLD WAY
    $segAirMultRand = (4/(3*$pi))*$massDensityAir*$segLens*$segDiams*
        ($airDragNormalCoeffs(1)+$airDragAxialCoeffs(1));
        
        pq($segAirMultRand);
		
=end comment

=cut
        # And for the fly:
    
    PrintSeparator("Setting up the dynamical variables");
    
    # PDL variables updated during the integration.  The dynamical variables are stored as 1-D PDL vectors.  Keep in mind that PDL matrices are indexed by column, then row:
    
    #in setting up pTheta's want horizontal, right moving momentum.  What does this mean for pTheta?
    
    my $t0;
	
    if ($loadedState->isempty){
        
        $t0 = $rps->{integration}{t0};
        $T0 = $t0;
        
        my ($qs0,$qDots0);
        
        my ($rodDxs0,$rodDys0,$rodDzs0);
        my ($lineDxs0,$lineDys0,$lineDzs0);

        if ($numRodSegs){
			($rodDxs0,$rodDys0,$rodDzs0)	= SetRodStartingConfig($rodSegLens);
        } else {
			($rodDxs0,$rodDys0,$rodDzs0)	= map {zeros(0)} (0..2)
		}
        
        if ($numLineSegs) {
            # Take the initial line configuration as straight, deflected from the horizontal by the specified angle offset (up is negative):
            #pq($lineSegLens);
            ($lineDxs0,$lineDys0,$lineDzs0)  = SetLineStartingConfig($lineSegLens);
            #pq($lineDxs0,$lineDys0,$lineDzs0);
        } else {
			($lineDxs0,$lineDys0,$lineDzs0)  = map {zeros(0)} (0..2);
		}
        
        #my $qDots0 = zeroes($qs0);
        # Implies all thetaDots and (dynamic) segDots zero, so all rod and line nodes still.
		
		#pq($rodDxs0,$rodDys0,$rodDzs0,$lineDxs0,$lineDys0,$lineDzs0);
 
        $qs0 = $rodDxs0->glue(0,$lineDxs0)
                ->glue(0,$rodDys0)->glue(0,$lineDys0)
                ->glue(0,$rodDzs0)->glue(0,$lineDzs0);
        
        $qDots0 = zeros($qs0);
        if ($verbose>=3){pq($qs0,$qDots0)}
        
        # It happens for us that all qDots zero implies all $ps are zero.  However, we could set up the calculation so that qDots were not all zero, so to protect ourselves, we set the ps in the general manner:
        $Dynams0 = $qs0->glue(0,$qDots0);   # On initialization, the second half holds starting qDots.  They are converted to ps before the first step.
        pq($Dynams0);
        

    }else{
        
        $T0 = $loadedT0;
        $Dynams0 = $loadedState;
        if ($verbose>=2){print "\nSTARTING INTEGRATION FROM STATE LOADED FROM ROD FILE.\n\n"}
    }
    
    $dT0	= $rps->{integration}{dt0};
    $dTPlot	= $rps->{integration}{plotDt};
    if ($verbose>=3){pq($T0,$Dynams0)}
	
	# Disable events mechanism:
    SetEventTs($T0,$T0-1,$T0-1);
    #SetEventTs($T0,$tipReleaseStartTime,$tipReleaseEndTime);
	
	my $holdingK	= eval($rps->{holding}{springConstOzPerIn})*$ouncesToDynes/$inchesToCms;
	my $holdingC	= eval($rps->{holding}{dampingConstOzSecPerIn})*$ouncesToDynes/$inchesToCms;
	
    my $runControlPtr          = \%runControl;
    my $loadedStateIsEmpty     = $loadedState->isempty;
    

    $paramsStr    = GetRodStr()."\n".GetLineStr()."\n".GetLeaderStr()."\n".GetTippetStr()."  ".GetFlyStr()."\n".GetAmbientStr()."\n".GetDriverStr()."\n".$integrationStr;
	
    #pq($numLineSegs);die;
    %opts_plot = (gnuplot=>$gnuplot);
	
	$T = undef;
	
    Init_Hamilton("initialize",
                    $nominalG,$rodLen,$rodActionLen,
                    $numRodSegs,$numLineSegs,
                    $segLens,$segDiams,
                    $segMasses,zeros(0),$segKs,$segCs, # stretch Ks and Cs only
					$rodBendKs, $rodBendCs,
					$holdingK, $holdingC,
                    $flyNomLen,$flyNomDiam,$flyMass,undef,
                    $dragSpecsNormal,$dragSpecsAxial,
                    $segAirMultRand,
                    $driverXSpline,$driverYSpline,$driverZSpline,
                    $driverDXSpline,$driverDYSpline,$driverDZSpline,
                    $frameRate,$driverStartTime,$driverEndTime,
                    $tipReleaseStartTime,$tipReleaseEndTime,
                    $T0,$Dynams0,$dT0,$dTPlot,
                    $runControlPtr,$loadedStateIsEmpty);
}


my (%opts_GSL,$t0_GSL,$t1_GSL,$dt_GSL);
my $elapsedTime_GSL;
my ($finalT,$finalState);
my ($plotTs,$plotXs,$plotYs,$plotZs,$plotNumRodNodes,$plotErrMsg);
my ($plotXLineTips,$plotYLineTips,$plotZLineTips,
    $plotXLeaderTips,$plotYLeaderTips,$plotZLeaderTips,
	$plotBottom);
my ($XTip0,$YTip0,$ZTip0);;
my $init_numLineSegs;
# These include the handle butt.
my $lineSegNomLens;	# I'm not sure I need this distinction (nom) any more.


sub DoRun {
    
    ## Do the integration.  Either begin run or continue. if $T is not a PDL we are initializing a run.  The initialization block of this function turns $T into a pdl, and it, plus times glued below it, store the reported results from the solver.  Parallel to $T is the pdl matrix $Dynams whose rows store the values of the dynamic variables associated with the reported times.
	
	# In general, this function will store just results corresponding to the uniform vector of times separated by the interval $dTPlot.  There is one exception to this:  If the solver makes a planned stop at an event time that is not one of the uniform times, its value and the associated dynamical values will be temporarily stored as the last entries in $T and $Dynams.  I do this so that if there is a subsequent user interrupt before the next uniform time, the run can continue from the event data, and not need to go back to the uniform time before that.  This is both more user friendly, and easier to implement.
	
	# When we next obtain a uniform data time and dynamical variables, the temporary values will be removed before the subsequent times and values are appended.
	
	# User interrupts are generated only by means of the PAUSE button on the control panel.  When one is caught, this function stores any good data the solver returns and plots all the uniform-interval data that has previously been collected by all the subsequent runs.  After an interrupt, and on a subsequent CONTINUE, this whole function will be run again, but a small, partial initialization that I call a restart.  The new run takes up where the previous one left off.  NOTE that the PAUSE button will only be reacted to during a call to DE, so in particular, while the solver is running.
	
	## To avoid ambiguity from comparisons of doubles, I have reduced all the timings passed to and from the integrator to multiples of secs/10000.  This was done in CheckParams() using DecimalRound().
	
    my $JACfac;
	#my $nextNumLineSegs;
	
    if (ref($T) ne 'PDL'){
	
    	PrintSeparator("\n*** Running the GSL solver ***",0,$verbose>=2);
		
        $init_numLineSegs   = $numLineSegs;
        
        $elapsedTime_GSL    = 0;
        
        $t0_GSL             = Get_T0();	# Should be $rps->{integration}{t0}.
        
        my $t1				= $rps->{integration}{t1};   # Requested end
        $dt_GSL             = $dTPlot;
		
        my $lastStep_GSL	= DecimalFloor(($t1-$t0_GSL)/$dt_GSL);
        $t1_GSL             = $t0_GSL+$lastStep_GSL*$dt_GSL;    # End adjusted to keep the reported step intervals constant.
		if ($verbose>=2 and $t1 != $t1_GSL){print "Reducing stop time to last uniform step, from $t1 to $t1_GSL\n"}
        
        $Dynams             = Get_DynamsCopy(); # This includes good initial $ps.
        if($verbose>=3){pq($t0_GSL,$t1_GSL,$dt_GSL,$Dynams)}
        
        
        $lineSegNomLens     = $segLens(-$init_numLineSegs:-1);
 
		# Adjust the events list (keep only those earlier than t1):
        #$holding	= ($eventTs->isempty) ? 0 : 1;
			# Turn holding on if there are any events set up, even if in the next operation we remove all of them (which means holding continues to the end of the run).	 NEEDS WORK
		
		# In the current implementation, holding is managed entirely by RHamilton3D and does not require event management here.  However, I leave the event mechanism in place since if we ever implement hauling, events will be needed.
        if (!$eventTs->isempty){
			# In the present implementation, there is no reduction in the number of line segments.  However we do let restart manage the $holding values:
			
			# Truncate and adjust the events list so that t1 becomes the final event:
			my $iEvents	= which($eventTs < $t1_GSL);
			$eventTs	= ($iEvents->isempty) ? zeros(0) : $eventTs($iEvents);
			$eventTs	= $eventTs->glue(0,pdl($t1_GSL));
			#pq($eventTs);

			if (DEBUG and $verbose>=2){pq($eventTs)}
			#if (DEBUG and $verbose>=3){pq($holding,$eventTs)}
			
            Init_Hamilton("restart_cast",$t0_GSL,$Dynams,$holding);
            #($XTip0,$YTip0,$ZTip0) = Get_Tip0();
			#pq($XTip0,$YTip0,$ZTip0);
        } else {
			if (DEBUG and $verbose>=2){print "REMEMBER, THERE ARE NEVER EVENTS IN CAST\n"}
		}
		
		
        my $h_init  = eval($rps->{integration}{dt0});
        %opts_GSL	= (type=>$rps->{integration}{stepperName},h_init=>$h_init);
        if ($verbose>=3){pq(\%opts_GSL)}
        
        $T = pdl($t0_GSL);   # To indicate that initialization has been done.  Prevents repeated initializations even if the user interrups during the first plot interval.
        
        if ($verbose>=2){print "Solver startup can be especially slow.  BE PATIENT.\n"}
        else {print "RUNNING SILENTLY, wait for return, or hit PAUSE to see the results thus far.\n"}
    }
	
	# "Next" in the sense that we are going to the top of the loop, where these will be converted to "this".
    my $nextStart_GSL   = $T(-1)->sclr;
	if (DEBUG and $verbose>=2){printf( "(Re)entering Run:\tt=%.5f\n",$nextStart_GSL)}
 	my $nextDynams_GSL	= $Dynams(:,-1);
	
    if ($verbose>=4){
        $JACfac = JACget();
        pq($JACfac);
    }
    
    # Run the solver:
    my $timeStart = time();
    my $tStatus = 0;
    my $tErrMsg = '';;
    my ($interruptT,$interruptDynams);
    #my $nextNumSegs;
    my $wasHolding;
    
    
    # Also, error scaling options. These all refer to the adaptive step size contoller which is well documented in the GSL manual.
    
    # epsabs and epsrel the allowable error levels (absolute and relative respectively) used in the system. Defaults are 1e-6 and 0.0 respectively.
    
    # a_y and a_dydt set the scaling factors for the function value and the function derivative respectively. While these may be used directly, these can be set using the shorthand ...
    
    # scaling, a shorthand for setting the above option. The available values may be y meaning {a_y = 1, a_dydt = 0} (which is the default), or yp meaning {a_y = 0, a_dydt = 1}. Note that setting the above scaling factors will override the corresponding field in this shorthand.
    
    ## See https://metacpan.org/pod/PerlGSL::DiffEq for the solver documentation.
    
    # I want the solver to return uniform steps of size $dt_GSL.  Thus, in the case of off-step returns (user or stripper interrupts) I need to make an additional one-step correction call to the solver, and edit its returns appropriately.  The correction step is always made with the new configuration and terminates on the next step.
    
    ## NextStart is always last report.  Also, each scheduled restart will be a last report.
    while ($nextStart_GSL < $t1_GSL) {
        
        my $thisStart_GSL = $nextStart_GSL;
        if (DEBUG and $verbose>=2){printf("\nt=%.4f   ",$thisStart_GSL)}
        
		my @tempArray = $nextDynams_GSL->list;
		my $theseDynams_GSL_aRef = \@tempArray;	# Can't figure out how to do this in 1 go.
		#my $reftype = ref($theseDynams_GSL_aRef);
		#pq($reftype); die;

        my $thisStop_GSL;
        my $thisNumSteps_GSL;
        my $nextEvent_GSL;
			# $iEvents, the index into $eventTs is global and persists between run calls.
		my $startIsUniform;
		my $startIsEvent;
        my $stopIsUniform;
        my $solution;
		
		# Just deal with the possible cases:
		#	thisStart is uniform, go to the uniform before next event or to the end.
		#		if there is no uniform before, go to next event, count =1.
		#	thisStart is not uniform. go to next uniform or next event.
		
		# if there are remaining events,
		# it doesn't matter if start is event or not, only if it is uniform or not.
		# it does matter for saving, but not for finding stop.
		# We do need to know what the next event, if any, is.
		
        if ($eventTs->isempty){
		   # No events, at least between t0 and t1.  Uniform starts and stops only.  On user interrupt, starts at last reported time.
			$startIsUniform		= 1;	# got here at $t0 or after user interrupt so on last reported step since no events.
			$thisStop_GSL		= $t1_GSL;
            $thisNumSteps_GSL	= DecimalFloor(($thisStop_GSL-$thisStart_GSL)/$dt_GSL);
            $stopIsUniform		= 1;

			if (DEBUG and $verbose>=2){print "thisStart_GSL=$thisStart_GSL,startIsUniform=$startIsUniform,thisStop_GSL=$thisStop_GSL,stopIsUniform=$stopIsUniform\n"}
        }
        else {    # There are events.
			
			# See where we are relative to them:
			my $iRemains	= which($eventTs >= $thisStart_GSL);
				# Will never be empty since t1 is an event, and we wouldn't be in the loop unless this time is less than that.
			$nextEvent_GSL	= $eventTs($iRemains(0))->sclr;

			# Are we actually starting at the next (actually this) event?
			if ($thisStart_GSL == $nextEvent_GSL){
				$startIsEvent	= 1;
				$nextEvent_GSL	= $eventTs($iRemains(1))->sclr;
					# There must be at least one more event, t1.
			} else {
				$startIsEvent = 0;
			}

			# Figure out the stop:
            #my $lastUniformStep	= POSIX::floor(($thisStart_GSL-$t0_GSL)/$dt_GSL);
            my $lastUniformStep	= DecimalFloor(($thisStart_GSL-$t0_GSL)/$dt_GSL);
            my $lastUniformStop = $t0_GSL + $lastUniformStep*$dt_GSL;
            $startIsUniform		= ($thisStart_GSL == $lastUniformStop) ? 1 : 0;
			
            if ($startIsUniform) {
				
				# There is always the t1 event.
				
                $thisNumSteps_GSL
					= DecimalFloor(($nextEvent_GSL-$thisStart_GSL)/$dt_GSL);
                if ($thisNumSteps_GSL){     # Make whole steps to just before the next restart.
                    $thisStop_GSL   = $thisStart_GSL + $thisNumSteps_GSL*$dt_GSL;
                    $stopIsUniform  = 1;
                } else {    # Need to make a single partial step to take us to the next event.  This should NOT take us to the end, since we started uniform and the adjusted t1 is also uniform.
                    $thisStop_GSL		= $nextEvent_GSL;
                    $thisNumSteps_GSL   = 1;
                    $stopIsUniform
						= ($thisStop_GSL == $lastUniformStop+$dt_GSL) ? 1 : 0;
						# It might be a uniform event.
                }
            }
            else { # start is not uniform, so make no more than one step.
                
                $thisNumSteps_GSL       = 1;
                
                my $nextUniformStop = $lastUniformStop + $dt_GSL;
                if ($nextEvent_GSL < $nextUniformStop) {
                    $thisStop_GSL   = $nextEvent_GSL;
                    $stopIsUniform  = 0;
                } else {
                    $thisStop_GSL   = $nextUniformStop;
                    $stopIsUniform  = 1;
                }
            }

			if (DEBUG and $verbose>=2){print "startIsEvent=$startIsEvent,nextEvent_GSL=$nextEvent_GSL,thisStop_GSL=$thisStop_GSL\nlastUniformStop=$lastUniformStop,startIsUniform=$startIsUniform,stopIsUniform=$stopIsUniform\n"}
        }
		
        if ($verbose>=2){print "\n SOLVER CALL: start=$thisStart_GSL, end=$thisStop_GSL, nSteps=$thisNumSteps_GSL\n\n"}
		
		my $startErr = $thisStart_GSL-$thisStop_GSL;
		my $startErrStr =  "Detected bad integration bounds ($thisStart_GSL >= $thisStop_GSL).\n";
        if($startErr > 0.01){die "ERROR: ".$startErrStr}
		elsif($startErr>=0){print "WARNING: ".$startErrStr}
		
        $solution = pdl(ode_solver([\&DEfunc_GSL,\&DEjac_GSL],[$thisStart_GSL,$thisStop_GSL,$thisNumSteps_GSL],$theseDynams_GSL_aRef,\%opts_GSL));
		
		# Immediately decimal round the returned times so that there will be no ambiguities in the comparisons below:
		my $returnedTs = $solution(0,:)->copy;
		#pq($returnedTs);
		$solution(0,:) .= DecimalRound($returnedTs);
		#pq($solution);
		
		if (DEBUG and $verbose>=2 and any($returnedTs != $solution(0,:))){
			$returnedTs = $returnedTs->flat;
			my $roundedTs	= $solution(0,:)->flat;
			my $diffs		= $returnedTs-$roundedTs;
			print "\nWARNING:  Detected non-decimal-rounded solver return time(s).\n";
			print "returnedTs \t$returnedTs\nroundedTs  \t$roundedTs\ndifferences\t$diffs\n";
			print "\n";
		}
		
        if ($verbose>=3){print "\n SOLVER RETURN \n\n"}
        #pq($tStatus,$solution);
        
        # Check immediately for a user interrupt:
        $tStatus = DE_GetStatus();
        $tErrMsg = DE_GetErrMsg();
        
        # If the solver decides to give up, it prints "error, return value=-1", but does not return that -1.  Instead, it returns the last good solution, so in particular, the returned solution time will not equal $thisStop_GSL.
        if ($tStatus == 0 and $solution(0,-1) < $thisStop_GSL){
            $tStatus = -1;  # I'll help it.
            $tErrMsg    = "User interrupt or solver error";
        }
        
        if ($tStatus){
            $interruptT         = Get_TDynam();
            $interruptDynams    = Get_DynamsCopy();
            if (DEBUG and $verbose>=4){pq($tStatus,$tErrMsg,$interruptT,$interruptDynams)}
        }
        
        # Start a subsequent run with the latest average dts of the just completed run:
        my $next_h_init = Get_movingAvDt();
        $opts_GSL{h_init} = $next_h_init;
        if (DEBUG and $verbose>=4){pq($next_h_init)}
        
        # If the solver returns the desired stop time, the step is asserted to be good, so keep the data.  Interrupts (set by the user, caught by TK, are only detected by DE() and passed to the solver.  So an iterrupt sent after the solver's last call to DE will be caught on the next solver call.
        
        # Always restart the while block (or the run call, if the stepper detected a user interrupt) with most recent good solver return.  That may not be on a uniform step if we were making up a partial step to a seg start:
		
		
        $nextStart_GSL  = $solution(0,-1)->sclr;
        $nextDynams_GSL = $solution(1:-1,-1)->flat;

        if (DEBUG and $verbose>=3){print "END_TIME=$nextStart_GSL\nEND_DYNAMS=$nextDynams_GSL\n\n"}
        #pq($T,$Dynams);

		
        # There  is always at least one time (starting) in solution.  Never keep the starting data:
        my ($nCols,$nTimes) = $solution->dims;
        
        if ($nextStart_GSL == $thisStop_GSL) {
			# Got to the planned end of block run (so there are at least 2 rows.
			# We will keep the stop data, whether or not the stop was uniform.  However if it was not, we'll get rid of it next pass through the loop.
		
			# However, if the start was not uniform, remove the last stored data row, which we can do because we have something more recent to start with next time:
			if (!$startIsUniform){
				$T		= $T(0:-2);
				$Dynams	= $Dynams(:,0:-2);
				if (DEBUG and $verbose>=2){pq($T,$Dynams)}
			}
        }
        
        # In any case, we never keep the run start data:
        $solution   = ($nTimes <= 1) ? zeros($nCols,0) : $solution(:,1:-1);
		
	
		# Record the data:
        $wasHolding = 0;	# Disable padding.
        #$wasHolding = $holding;
        my ($ts,$paddedDynams) = PadSolution($solution,$wasHolding);
			# Just gives back the keeper dynams in the solution.
		
		$T		= $T->glue(0,$ts);
		$Dynams	= $Dynams->glue(1,$paddedDynams);
		if (DEBUG and $verbose>=4){pq($T,$Dynams)}
		
        if ($nextStart_GSL < $t1_GSL and $tStatus >= 0) {
            # On any restart, if either no error, or user interrupt.  Resets Hamilton's status:
			#Init_Hamilton("restart_cast",$nextStart_GSL,$nextNumLineSegs,$nextDynams,$holding);
			#Init_Hamilton("restart_cast",$nextStart_GSL,$nextDynams_GSL,$holding);
			Init_Hamilton("restart_cast",$nextStart_GSL,$nextDynams_GSL);
        }
		
        if ($tStatus){last}
    }
    
    my $timeEnd = time();
    $elapsedTime_GSL += $timeEnd-$timeStart;
    
    if ($verbose>=3){
        my $JACfac = JACget();
        pq($JACfac);
    }
    
    
    if (DEBUG and $verbose>=4){print "After run\n";pq($T,$Dynams)};
    
    $finalT     = $T(-1)->flat;
    $finalState = $Dynams(:,-1)->flat;
    #pq($finalT,$finalState);
    
    $plotTs = zeros(0);
    
    $plotNumRodNodes    = $numRodNodes+1;   #includes handle butt and handle top.
    my $numPlotNodes    = $numSegs+2;       #includes handle butt and handle top.
    ($plotXs,$plotYs,$plotZs) = map {zeros($numPlotNodes,0)} (0..2);

    my $plotRs = zeros($numSegs,0);
    
    ($plotXLineTips,$plotYLineTips,$plotZLineTips)          = map {zeros(1,0)} (0..2);
    ($plotXLeaderTips,$plotYLeaderTips,$plotZLeaderTips)    = map {zeros(1,0)} (0..2);
    
    #my $nextPlotTime = $tt[0];
    
    #my $iTrace=0;
    #my $iLastPlotted = -1;
    my $tPlot;
    my $traceCount = $T->nelem;
    for (my $ii=0;$ii<$traceCount;$ii++){
        
        # So, if we got here, either this is the next requested trace to plot or it is bad and the previous step was not plotted.
        
        $tPlot = $T($ii)->sclr;
        my $tDynams = $Dynams(:,$ii);
        if (DEBUG and $verbose>=5){pq($ii,$tDynams);print "\n";}
        
        my ($tXs,$tYs,$tZs,$tRs,$XLineTip,$YLineTip,$ZLineTip,$XLeaderTip,$YLeaderTip,$ZLeaderTip) =
                Calc_Qs($tPlot,$tDynams,$lineTipOffset,$leaderTipOffset,1);
        
        if (DEBUG and $verbose>=5){pq($tXs,$tYs,$tZs)}
        
        #pq($XLineTip,$XLeaderTip);
        #die;
        
        $plotTs = $plotTs->glue(0,pdl($tPlot));
        $plotXs = $plotXs->glue(1,$tXs);
        $plotYs = $plotYs->glue(1,$tYs);
        $plotZs = $plotZs->glue(1,$tZs);
        $plotRs = $plotRs->glue(1,$tRs);
        
        $plotXLineTips      = $plotXLineTips->glue(1,$XLineTip);
        $plotYLineTips      = $plotYLineTips->glue(1,$YLineTip);
        $plotZLineTips      = $plotZLineTips->glue(1,$ZLineTip);
        
        $plotXLeaderTips    = $plotXLeaderTips->glue(1,$XLeaderTip);
        $plotYLeaderTips    = $plotYLeaderTips->glue(1,$YLeaderTip);
        $plotZLeaderTips    = $plotZLeaderTips->glue(1,$ZLeaderTip);
        
    }
    #pq($traceCount,$plotTs,$plotXs,$plotYs);
    
    if ($tStatus){
        
        # Stepper was interrupted.  Get the last data given to DE (probably unreliable) and plot it to show the user where the integration was trying to go.
        
        #pq($interruptT);
        
        #        if ($interruptT > $nextStart_GSL) {
        # Make a solution-like pdl:
        my $interruptSolution   = pdl($interruptT)->glue(0,$interruptDynams);
        
        my ($tt,$tDynams) = PadSolution($interruptSolution,$wasHolding);
        
        my ($tXs,$tYs,$tZs,$tRs,$XLineTip,$YLineTip,$ZLineTip,$XLeaderTip,$YLeaderTip,$ZLeaderTip) =
                Calc_Qs($tPlot,$tDynams,$lineTipOffset,$leaderTipOffset,1);
        if (DEBUG and $verbose>=5){pq($tXs,$tYs,$tZs)}
        
        
        $plotTs = $plotTs->glue(0,pdl($tt));
        $plotXs = $plotXs->glue(1,$tXs);
        $plotYs = $plotYs->glue(1,$tYs);
        $plotZs = $plotZs->glue(1,$tZs);
        $plotRs = $plotRs->glue(1,$tRs);
        
        $plotXLineTips      = $plotXLineTips->glue(1,$XLineTip);
        $plotYLineTips      = $plotYLineTips->glue(1,$YLineTip);
        $plotZLineTips      = $plotZLineTips->glue(1,$ZLineTip);
        
        $plotXLeaderTips    = $plotXLeaderTips->glue(1,$XLeaderTip);
        $plotYLeaderTips    = $plotYLeaderTips->glue(1,$YLeaderTip);
        $plotZLeaderTips    = $plotZLeaderTips->glue(1,$ZLeaderTip);
        
        if (DEBUG and $verbose>=5){
            print "Appending interrupt data\n";
            pq($tt,$tXs,$tYs,$tZs);
        }
        #        }
    }
    
    
    if (DEBUG and $verbose>=5){pq($plotTs,$plotXs,$plotYs,$plotZs,$plotRs)}
    if (DEBUG and $verbose>=5){pq($plotXLineTips,$plotYLineTips,$plotZLineTips,$plotXLeaderTips,$plotYLeaderTips,$plotZLeaderTips)}
    
    
    PrintSeparator("\nOn solver return",2);
    if ($verbose>=2){
        
        my ($DE_numCalls,$DEfunc_numCalls,$DEjac_numCalls) = DE_GetCounts();
        pq($DE_numCalls,$DEfunc_numCalls,$DEjac_numCalls,$elapsedTime_GSL);
    }
    
    
    # Plot to x11 terminal and write plotting file:
    
    my $duration = sprintf("%04d",1000*sclr($plotTs(-1)));
    $rps->{file}{save} = '_'.$runIdentifier.'_'.$duration;
    
    $plotErrMsg = $tErrMsg;
    
    #pq $plotErrMsg;
    
    my $titleStr = "RCast - " . $dateTimeLong;
    
	
	$plotBottom = 0;

    RCommonPlot3D('window',$rps->{file}{save},$titleStr,$paramsStr,
    $plotTs,$plotXs,$plotYs,$plotZs,$plotXLineTips,$plotYLineTips,$plotZLineTips,$plotXLeaderTips,$plotYLeaderTips,$plotZLeaderTips,$plotNumRodNodes,$plotBottom,$plotErrMsg,$verbose,\%opts_plot);
    
	
    
    # If integration has completed, tell the caller:
    if ($tPlot>=$t1_GSL or $tStatus < 0) {
        if ($tStatus < 0){print "\n";pq($tStatus,$tErrMsg)}
        &{$runControl{callerStop}}();
    }    
}



sub UnpackDynams {
    my ($dynams) = @_;
    
    my $numCols = $dynams->dim(0);
    my $numSegs = $numCols/6;

    my $dxs     = $dynams(0:$numSegs-1,:);
    my $dys     = $dynams($numSegs:2*$numSegs-1,:);
    my $dzs     = $dynams(2*$numSegs:3*$numSegs-1,:);
    
    my $dxps    = $dynams(3*$numSegs:4*$numSegs-1,:);
    my $dyps    = $dynams(4*$numSegs:5*$numSegs-1:);
    my $dzps    = $dynams(5*$numSegs:-1,:);
    
    return ($dxs,$dys,$dzs,$dxps,$dyps,$dzps);
}


sub UnpackSolution {
    my ($solution) = @_;
    
    my $ts  = $solution(0,:);
    my ($dxs,$dys,$dzs,$dxps,$dyps,$dzps) = UnpackDynams($solution(1:-1,:));
    
    return ($ts,$dxs,$dys,$dzs,$dxps,$dyps,$dzps);
}


sub StripDynams {
    my ($dynams) = @_;
    
    ## Strip for holding.  That is, remove the last line segment (the one nearest the fly).
    
    #pq($dynams);
    
    if ($dynams->dim(1) != 1){die "ERROR:  StripDynams requires exactly one row.\n"}
    
    my ($dxs,$dys,$dzs,$dxps,$dyps,$dzps) = UnpackDynams($dynams->flat);
    
    #pq($dthetas,$dxs,$dys,$dthetaps,$dxps,$dyps);
    
    my $strippedDynams =
        $dxs(0:-2)->glue(0,$dys(0:-2))->glue(0,$dzs(0:-2))
        ->glue(0,$dxps(0:-2))->glue(0,$dyps(0:-2))->glue(0,$dzps(0:-2))->flat;
    
    #pq($strippedDynams);
    
    return $strippedDynams;
}

sub RestoreDynams {
    my ($ts,$dynams) = @_;
    
    ## Add back the concocted last segment dynamical variables.
    
    my ($dxs,$dys,$dzs,$dxps,$dyps,$dzps) = UnpackDynams($dynams);
	
	my $numTs = (ref($ts) eq 'PDL') ? $ts->nelem : 1;
    my ($Xs,$Ys,$Zs);
	if ($numTs>1){
    	($Xs,$Ys,$Zs) = map {zeros(0)} (0..2);
		for (my $i=0; $i<$numTs; $i++){
			my ($tXs,$tYs,$tZs)  = Calc_Qs($ts($i),$dynams(:,$i)->flat);
			#pq($tXs,$tYs,$tZs);
			$Xs = $Xs->glue(1,$tXs);
			$Ys = $Ys->glue(1,$tYs);
			$Zs = $Zs->glue(1,$tZs);
			#pq($Xs,$Ys,$Zs);
		}
		#pq($Xs,$Ys,$Zs);
	} else {
		($Xs,$Ys,$Zs)  = Calc_Qs($ts,$dynams);
	}
	
	#pq($Xs,$Ys,$Zs);
	
    my $dxLast = $XTip0-$Xs(-1,:);
    my $dyLast = $YTip0-$Ys(-1,:);
    my $dzLast = $ZTip0-$Zs(-1,:);
	
	my $zerosPad = zeros(1,$numTs);
	
	#pq($XTip0,$YTip0,$ZTip0);
	#pq($dxLast,$dyLast,$dzLast);
    
    my $restoredDynams =
        $dxs->glue(0,$dxLast)->glue(0,$dys)->glue(0,$dyLast)->glue(0,$dzs)->glue(0,$dzLast)
        ->glue(0,$dxps)->glue(0,$zerosPad)->glue(0,$dyps)->glue(0,$zerosPad)->glue(0,$dzps)->glue(0,$zerosPad);
    
    ### ??? Actually, is setting the last segment momenta correct.  Any mass associated with it would be moving due to stretching.  Should really put in the appropriate qDots and then set ps from them.
    
    #pq($restoredDynams);
	
    return $restoredDynams;
}


sub PadSolution {
    my ($solution,$holding) = @_;
    
    #print "In pad\n";
    ## Adjust for the varying number of nodes due to holding.
    
    if ($solution->isempty){return (zeros(0),zeros(0))}
    #pq($solution);
    
    my $ts      = $solution(0,:)->flat;
    my $dynams  = $solution(1:-1,:);
    #pq($ts,$dynams);
    
    my ($dxs,$dys,$dzs,$dxps,$dyps,$dzps) = UnpackDynams($dynams);
    #pq($dxs,$dys,$dzs,$dxps,$dyps,$dzps);
    
    if ($holding != 1){return ($ts,$dynams)}
    
    # So, the last line segment dynmical variables must be inserted:
    my $paddedDynams = RestoreDynams($ts,$dynams);
    
    #pq($ts,$paddedDynams);
    return ($ts,$paddedDynams);
}



sub Calc_Qs {
    my ($t,$tDynams,$lineTipOffset,$leaderTipOffset,$includeHandleButt) = @_;
    
    my $nargin = @_;
    #pq($nargin);
	
	if (ref($t) eq 'PDL'){$t=$t->sclr}
    ## Return the cartesian coordinates Xs, Ys and Zs of all the rod and line NODES.  These are used for plotting and saving.
    my ($driverX,$driverY,$driverZ,$driverDX,$driverDY,$driverDZ) = Calc_Driver($t,0);
		# Suppress printing in Calc_Driver.
    
    #pq($driverX,$driverY,$driverZ);
    
    my ($dxs,$dys,$dzs) = UnpackDynams($tDynams);
    #    pq($dthetas,$dxs,$dys);
    #pq($driverX,$driverY,$driverTheta);
    
    my $drs = sqrt($dxs**2+$dys**2+$dzs**2);
    
    my $dXs = pdl($driverX)->glue(0,$dxs);
    my $dYs = pdl($driverY)->glue(0,$dys);
    my $dZs = pdl($driverZ)->glue(0,$dzs);
    #pq($dXs,$dYs);
    
    my $Xs = cumusumover($dXs);
    my $Ys = cumusumover($dYs);
    my $Zs = cumusumover($dZs);
    
    
    if ($includeHandleButt){
        $Xs = ($Xs(0) - $driverDX)->glue(0,$Xs);
        $Ys = ($Ys(0) - $driverDY)->glue(0,$Ys);
        $Zs = ($Zs(0) - $driverDZ)->glue(0,$Zs);
    }
    
    if (DEBUG and $verbose>=5){print "Calc_Qs:\n Xs=$Xs\n Ys=$Ys\n Zs=$Zs\n drs=$drs\n"}


    my ($XLineTip,$YLineTip,$ZLineTip,$XLeaderTip,$YLeaderTip,$ZLeaderTip);
    if ($nargin > 2){
        ($XLineTip,$YLineTip,$ZLineTip) =
            Calc_QOffset($Xs,$Ys,$Zs,$drs,$lineTipOffset);
        #pq($XLineTip);pqInfo($XLineTip);
        #die;
    }
    if ($nargin > 3){
        ($XLeaderTip,$YLeaderTip,$ZLeaderTip)  =
            Calc_QOffset($Xs,$Ys,$Zs,$drs,$leaderTipOffset);
    }
    
    if (DEBUG and $verbose>=5){pq($XLineTip,$YLineTip,$ZLineTip,$XLeaderTip,$YLeaderTip,$ZLeaderTip)}
	
    return ($Xs,$Ys,$Zs,$drs,$XLineTip,$YLineTip,$ZLineTip,$XLeaderTip,$YLeaderTip,$ZLeaderTip);
}


sub Calc_QOffset {
    my ($Xs,$Ys,$Zs,$drs,$offset) = @_;
    
    ## For plotting line and leader tip locations. Expects padded data. Note that the fractional position in the segs should be based on nominal seg lengths, since these positions stretch and contract with the material. Note that holding does not change the number of plotted segs.
    
    #pq($Xs,$Ys,$drs,$offset);
    
    my $revNodeOffsets  = cumusumover(pdl(0)->glue(0,$lineSegNomLens(-1:0)));
    my $iMax            = $revNodeOffsets->nelem - 1;
    
    my $iNext   = which($revNodeOffsets > $offset);
    if ($iNext->isempty){
        return (pdl($nan),pdl($nan),pdl($nan));     # These won't plot.
    }
    $iNext      = $iNext(0)->sclr;
    my $iThis   = $iNext-1;
    
    my $fract   = ($offset-$revNodeOffsets($iThis))/
    ($revNodeOffsets($iNext)-$revNodeOffsets($iThis));
    
    my $revXs = $Xs(-1:0);
    my $revYs = $Ys(-1:0);
    my $revZs = $Zs(-1:0);
    
    my $XOffset    = (1-$fract)*$revXs($iThis) + $fract*$revXs($iNext);
    my $YOffset    = (1-$fract)*$revYs($iThis) + $fract*$revYs($iNext);
    my $ZOffset    = (1-$fract)*$revZs($iThis) + $fract*$revZs($iNext);
    
    return ($XOffset,$YOffset,$ZOffset);
}



# SVG FILE UTILITIES ===================================================================

# The cast drawing is expected to be in SVG.  See http://www.w3.org/TR/SVG/ for the full protocol.  SVG does 2-DIMENSIONAL drawing only!  Transformations nest:  apply innermost transformation to innermost vector to get the vector expressed in the next coordinate system out.  If there is a transformation outside that, apply it to what you got to get the vector in the next outer coords.  And so forth until you get to the outermost (canvas) coords.  See the function SVG_matrix() below for the details.

# In particular, from Wikipedia:
# Paths - Simple or compound shape outlines are drawn with curved or straight lines that can be filled in, outlined, or used as a clipping path. Paths have a compact coding. For example M (for 'move to') precedes initial numeric x and y coordinates and L (line to) precedes a point to which a line should be drawn. Further command letters (C, S, Q, T and A) precede data that is used to draw various Bézier and elliptical curves. Z is used to close a path. In all cases, absolute coordinates follow capital letter commands and relative coordinates are used after the equivalent lower-case letters.

# These are barebones functions just adequate to handle my drawing simple segments.
# $seg=pdl($x0,$y0,$x1,$y1).

sub SVG_matrix {
    my ($a,$b,$c,$d,$e,$f,$inSeg) = @_;

#print "in matrix\n";
    my $mat = pdl($a,$c,$e,$b,$d,$f,0,0,1)->reshape(3,3);
    $inSeg = $inSeg->reshape(2,2)->transpose->glue(1,ones(2));    
#pq($mat,$inSeg);
    
    my $outSeg = $mat x $inSeg;
#pq $outSeg";

    return $outSeg(:,0:1)->transpose->flat;
}


sub SVG_translate {
    my ($tx,$ty,$inSeg) = @_;

#print "in trans\n";    
    return SVG_matrix(1,0,0,1,$tx,$ty,$inSeg);
}



sub SVG_ApplyTransformToSeg {
    my ($transform,$content,$Xs,$Ys) = @_;
    
    # WARNING:  This code applies only a single transformation.  The user needs to make sure that there are no nested transformations!  It is ok to ignore the single global transformation.
    
#pq($transform,$content);        
    my $seg = $Xs(0)->glue(0,$Ys(0))->glue(0,$Xs(1))->glue(0,$Ys(1));    
#pq $seg;

    my $ok = 0;                                                        
    switch($transform) {
        case "matrix"       {
            if ($content =~ m[^(-?\d+?\.?\d*?),(-?\d+?\.?\d*?),(-?\d+?\.?\d*?),(-?\d+?\.?\d*?),(-?\d+?\.?\d*?),(-?\d+?\.?\d*?)$]) {
                $ok = 1;
                $seg = SVG_matrix($1,$2,$3,$4,$5,$6,$seg);
            }
        }
        case "translate"    {
            if ($content =~ m[^(-?\d+?\.?\d*?),(-?\d+?\.?\d*?)$]) {
                $ok = 1;
                $seg = SVG_translate($1,$2,$seg);
            }
        }
        else    {die "\n\nDectected unimplemented transform ($transform).\n\n"}
    }
    
    if (!$ok) { die "\n\nDetected bad argument:  $transform($content)\n"}

#pq $seg;
    my ($outXs,$outYs) = ($seg(0)->glue(0,$seg(2)),$seg(1)->glue(0,$seg(3)));        
}




# FUNCTIONS USED IN SETTING UP THE MODEL AND THE INTEGRATION ======================================


sub GetRodStr {
    
    my $str = "Rod=$rodIdentifier; LineActiveLen(ft)=$loopActiveLenFt\n";
    $str .= "ROD:  Lens(total,action)=($rodLenFt,$rodActionLenFt); NumPieces=$numPieces; Type=$sectionType;";
    $str .= " Mults(Ferrule,V&G)=($rps->{rod}{ferruleKsMult},$rps->{rod}{vAndGMultiplier});\n";
    $str .= " Dens,ZeroThick,WallThick=($rps->{rod}{densityLbFt3},$rps->{rod}{zeroFiberThicknessIn},$rps->{rod}{maxWallThicknessIn});";
    $str .= " Mods(elastic,dampStretch,dampBend)=($rps->{rod}{elasticModulusPSI},$rps->{rod}{dampingModulusStretchPSI},$rps->{rod}{dampingModulusBendPSI})";
	
    return $str;
}

sub GetLineStr {
    
    my $str .= "LINE: ID=$rps->{line}{identifier};";
    $str .= " NomWt,NomDiam,CoreDiam=($rps->{line}{nomWtGrsPerFt},$rps->{line}{nomDiameterIn},$rps->{line}{coreDiameterIn});";
    $str .= " Len==$rps->{line}{activeLenFt};";
    $str .= " Mods(elastic,damping)=($rps->{line}{coreElasticModulusPSI},$rps->{line}{dampingModulusPSI})";
    
    return $str;
}


sub GetLeaderStr {
    
    my $str = "LEADER: ID=$leaderStr;";
    $str .= " NomWt,Diam=($rps->{leader}{wtGrsPerFt},$rps->{leader}{diamIn}); ";
    $str .= " Len=$leaderLenFt; ";
    $str .= " Mods(elastic,damping)=($leaderElasticModPSI,$leaderDampingModPSI)";
    
    return $str;
}


sub GetTippetStr {
    
    my $str = "TIPPET: ID=$tippetStr; ";
    $str .= " Diam=$rps->{tippet}{diamIn}; ";
    $str .= " Len=$tippetLenFt; ";
    $str .= " Mods(elastic,damping)=($tippetElasticModPSI,$tippetDampingModPSI)";
    
    return $str;
}


sub GetFlyStr {
    
    my $str = "FLY: Wt=$rps->{fly}{wtGr}; ";
    $str .= " NomDiam,NomLen=($rps->{fly}{nomDiamIn},$rps->{fly}{nomLenIn}); ";
	
    return $str;
}


sub GetAmbientStr {
    
    my $str = "AMBIENT: Gravity=$rps->{ambient}{nominalG}; ";
    $str .= "DragSpecsNormal=($rps->{ambient}{dragSpecsNormal}); ";
    $str .= "DragSpecsAxial=($rps->{ambient}{dragSpecsAxial})";
    
    return $str;
}


sub GetDriverStr {
	
	my $isPar = ($driverIdentifier eq "Parameterized");
	
    my $str = "DRIVER: ID=$driverIdentifier; ";
	$str .= "t=($driverStartTime,";
	if ($isPar){$str .= "$rps->{driver}{powerVMaxTime},$rps->{driver}{powerEndTime},$rps->{driver}{driftStartTime},"}
	$str .= "$driverEndTime); ";
	if ($isPar){
		$str .= "Coords(s,e,p)=(($rps->{driver}{powerStartCoordsIn}),($rps->{driver}{powerEndCoordsIn}),($rps->{driver}{powerPivotCoordsIn}));\n";
		$str .= "Track(curve,skew)=($rps->{driver}{powerCurvInvIn},$rps->{driver}{powerSkewness}); ";
		$str .= " Handle(sDeg,eDeg,skew)=($rps->{driver}{powerHandleStartDeg},$rps->{driver}{powerHandleEndDeg}),$rps->{driver}{powerHandleSkewness}); ";
		$str .= " Drift(eDeg,skew)=($rps->{driver}{driftHandleEndDeg},$rps->{driver}{driftVelSkewness})";
	} else { $str .= "Coords(start)=($rps->{driver}{powerStartCoordsIn})"}
}

# SPECIFIC PLOTTING FUNCTIONS ======================================


sub PlotHandleSplines {
    my ($numTs,$driverXSpline,$driverYSpline,$driverZSpline,
        $driverDXSpline,$driverDYSpline,$driverDZSpline,$plot3D) = @_;
	
	## Expects distances in inches.
    
    my ($dataXs,$dataYs,$dataZs,$dataDXs,$dataDYs,$dataDZs) = map {zeros($numTs)} (0..5);
    #pq($dataXs,$dataYs,$dataZs);
    
    my $dataTs = $timeXs(0)+sequence($numTs)*($timeXs(-1)-$timeXs(0))/($numTs-1);
    #pq($dataTs);
    
    for (my $ii=0;$ii<$numTs;$ii++) {
        
        my $tt = $dataTs($ii)->sclr;
        
        $dataXs($ii) .= $driverXSpline->evaluate($tt);
        $dataYs($ii) .= $driverYSpline->evaluate($tt);
        $dataZs($ii) .= $driverZSpline->evaluate($tt);
        
        $dataDXs($ii) .= $driverDXSpline->evaluate($tt);
        $dataDYs($ii) .= $driverDYSpline->evaluate($tt);
        $dataDZs($ii) .= $driverDZSpline->evaluate($tt);
        
    }
	
	# Convert to inches:
	$dataXs /= $inchesToCms;
	$dataYs /= $inchesToCms;
	$dataZs /= $inchesToCms;

    #pq($dataXs,$dataYs,$dataZs);
    #pq($dataDXs,$dataDYs,$dataDZs);
	my %opts;

	if (!$plot3D){
		%opts = (gnuplot=>$gnuplot);
		Plot($dataTs,$dataXs,"X",$dataTs,$dataYs,"Y",$dataTs,$dataZs,"Z","Handle top splines as functions of time (inches)",\%opts);

		Plot($dataTs,$dataDXs,"DX",$dataTs,$dataDYs,"DY",$dataTs,$dataDZs,"DZ","Handle direction splines as functions of time (dimensionless)",\%opts);
	}
	else {
        %opts = (gnuplot=>$gnuplot,xlabel=>"x-axis(in)",ylabel=>"y-axis(in)",zlabel=>"z-axis(in)");
        Plot3D($dataXs,$dataYs,$dataZs,"Splined Handle Top Track (in)",\%opts);

		%opts = (gnuplot=>$gnuplot,xlabel=>"x-direction",ylabel=>"y-direction",zlabel=>"z-direction");
		Plot3D($dataDXs,$dataDYs,$dataDZs,"Toward handle top",pdl(0),pdl(0),pdl(0),"Handle bottom","Splined Handle Directions Track (dimensionless)",\%opts);
	}
}




sub DoSave { my $verbose = 1?$verbose:0;
    my ($filename) = @_;

    my($basename, $dirs, $suffix) = fileparse($filename);
#pq($basename,$dirs$suffix);

    $filename = $dirs.$basename;
    if ($verbose>=2){print "Saving to file $filename\n"}

    my $titleStr = "RCast - " . $dateTimeLong;

    if ($rps->{integration}{savePlot}){
        RCommonPlot3D('file',$dirs.$basename,$titleStr,$paramsStr,
                    $plotTs,$plotXs,$plotYs,$plotZs,$plotXLineTips,$plotYLineTips,$plotZLineTips,$plotXLeaderTips,$plotYLeaderTips,$plotZLeaderTips,$plotNumRodNodes,$plotBottom,$plotErrMsg,$verbose,\%opts_plot);
    }

#pq($plotTs,$plotXs,$plotYs,$plotZs);
                   
    if ($rps->{integration}{saveData}){
        RCommonSave3D($dirs.$basename,$rSwingOutFileTag,$titleStr,$paramsStr,
        $plotTs,$plotXs,$plotYs,$plotZs,$plotXLineTips,$plotYLineTips,$plotZLineTips,$plotXLeaderTips,$plotYLeaderTips,$plotZLeaderTips,$plotNumRodNodes,$plotBottom,$plotErrMsg,
        $finalT,$finalState,$segLens);
    }
}


sub RCastPlotExtras {
    my ($filename) = @_;
    
    if ($rps->{driver}{plotSplines}){PlotHandleSplines('file',121,$filename.'_driver')}

    my ($plotLineVXs,$plotLineVYs,$plotLineVAs,$plotLineVNs,$plotLine_rDots) = Get_ExtraOutputs();
    
    if ($rps->{integration}{plotLineVXs}){PlotMat($plotLineVXs,1000,"Line Node VXs - $dateTimeLong",'ONLY'.$filename.'_vx')}
    if ($rps->{integration}{plotLineVYs}){PlotMat($plotLineVYs,1000,"Line Node VYs - $dateTimeLong",'ONLY'.$filename.'_vy')}

    if ($rps->{integration}{plotLineVAs}){PlotMat($plotLineVAs,1000,"Line Node VAs - $dateTimeLong",'ONLY'.$filename.'_va')}
    if ($rps->{integration}{plotLineVNs}){PlotMat($plotLineVNs,1000,"Line Node VNs - $dateTimeLong",'ONLY'.$filename.'_vn')}

    if ($rps->{integration}{plotLine_rDots}){PlotMat($plotLine_rDots,1000,"ONLYLine Node rDots - $dateTimeLong",'ONLY'.$filename.'_rDot')}
}



# Required package return value:
1;

__END__

=head1 NAME

RCast3D - The principal organizer of the RHexCast3D program.  Sets up and runs the GSL ode solver and plots and saves its output.

=head1 SYNOPSIS

  use RCast3D;
 
=head1 DESCRIPTION

The functions in this file are used pretty much in the order they appear to gather and check parameters entered in the control panel and to load user selected specification files, then to build a line and stream model which is used to initialize the hamilton step function DE().  The definition of DE() requires nearly all the functions contained in the RHexHamilton3D.pm module.  A wrapper for the step function is passed to the ode solver, which integrates the associated hamiltonian system to simulate the swing dynamics.  After the run is complete, or if the user interrupts the run via the pause or stop buttons on the control panel, code here calls RCommonPlot3D.pm to create a 3D display of the results up to that point. When paused or stopped, the user can choose to save the integration results to .eps or .txt files, or both.

=head2 EXPORT

The principal exports are DoSetup, DoRun, and DoSave.  All the exports are used only by RHexCast3D.pl

=head1 AUTHOR

Rich Miller, E<lt>rich@ski.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2019 by Rich Miller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.28.1 or,
at your option, any later version of Perl 5 you may have available.

=cut

