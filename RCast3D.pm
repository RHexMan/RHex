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





### See "About the calculation" just before the subroutine SetupIntegration() for a discussion of the general setup for the calculation.  Documentation for the individual setup and run parameters may found just below, where the fields of rCastRunParams are defined and defaulted.


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
#  17/10/01 - See RHexStatic (17/09/29).  Understood the model a bit better:  the angle theta are the dynamical variables and act at the nodes (hinges), starting at the handle top and ending at the node before the tip.  The bending at these locations creates torques that tend to straighten the angles (see GradedSections()).  The masses, however, are properly located at the segment cg's, and under the effect of gravity, they also produce torques at the nodes.  In equilibrium, these two sets of torques must cancel.  Note that there is no need for the masses to be in any particular configuration with respect to the hinges or the stretches - the connection is established by the partials matrix, in this case, dCGQs_dqs (in fact, also d2CGQs_d2thetas for Calc_pDotsKE). There remains a delicacy in that the air drag forces should more properly be applied at the segment surface resistance centers, which are generally slightly different from the segment cgs.  However, to avoid doubling the size of the partials matrices, I will content myself with putting the air drags at the cg's.
#  17/10/08 - For a while I believed that I needed to compute cartesian forces from the tension of the line on the guides.  This is wrong.  Those forces are automatically handled by the constraints.  However, it does make sense to take the length of the section of line between the reel and the first line node (say a mark on the line, always outside the rod tip) as another dynamical variable.  The position of the marked node in space is determined by the seg length and the direction defined by the two components of the initial (old-style) line segment.  To first approximation, there need not be any mass associated with the line-in-guides segment since that mass is rather well represented by the extra rod mass already computed, and all the line masses outboard cause the new segment to have momentum.  What might be gained by this extra complication is some additional shock absorbing in the line.

#  17/10/30 - Modified to use the ODE solver suite in the Gnu Scientific Library.  PerlGSL::DiffEq provides the interface.  This will allow the selection of implicit solvers, which, I hope, will make integration with realistic friction couplings possible.  It turns out to be well known that friction terms can make ODE's stiff, with the result that the usual, explicity solvers end up taking very small time steps to avoid going unstable.  There is considerable overhead in implicit solutions, especially since they require jacobian information.  Providing that analytically in the present situation would be a huge problem, but fortunately numerical methods are available.  In particular, I use RNumJac, a PDL version of Matlab's numjac() function that I wrote.

### TO DO:
# Get TK::ROText to accept \r.
# Add hauling and wind velocity.


# Compile directives ==================================
package RCast3D;

use warnings;
use strict;

use Exporter 'import';
our @EXPORT = qw(DEBUG $verbose $debugVerbose $vs $tieMax %rCastRunParams %rCastRunControl $rCastOutFileTag RCastSetup LoadRod LoadLine LoadDriver RCastRun RCastSave RCastPlotExtras);

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

our $tieMax = 2;
    # Values of verbose greater than this cause stdout and stderr to go to the terminal window, smaller values print to the widget's status window.  Set to -1(?) for serious debugging.


# Declare variables and set defaults  -----------------
our $rCastOutFileTag = "#RCastOutputFile";




our %rCastRunParams = (file=>{},rod=>{},line=>{},ambient=>{},driver=>{},integration=>{},misc=>{});
    ### Defined just below.

### !!!! NOTE that after changing this structure, you should delete the widget prefs file.

my $rps = \%rCastRunParams;

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
	numSections			=> 2,
    sectionItem     	=> 0,
    sectionName			=> "section - hex",
	buttDiamIn			=> 0.350,
	tipDiamIn			=> 0.080,
    fiberGradient       => 0.0, # Zero for uniform.  In 1/inches to drop from 1 to 0.  Higher numbers soften the rod generally, but stiffen the tip relative to the base.
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
    # Total desired length from rod tip to fly.
    identifier              => "",
    nomWtGrsPerFt            => 6,
    # This is the nominal.  If you are reading from a file, must be an integer.
    nomDiameterIn           => 0.060,
    coreDiameterIn          => 0.020,
    # Make a guess.  Used in computing effective Hook's Law constant from nominal elastic modulus.
    coreElasticModulusPSI   => 1.52e5,        # 2.5e5 seems not bad, but the line hangs in a curve to start so ??
    # I measured the painted 4 wt line (tip 12'), and got corresponding to assumed line core diam of 0.02", EM = 1.52e5.
    # Try to measure this.  Ultimately, it is probably just the modulus of the core, with the coating not contributing that much.  0.2 for 4 wt line, 8' long is ok.  For 20' 7wt, more like 2.  This probably should scale with nominal line weight.   A tabulated value I found for Polyamides Nylon 66 is 1600 to 3800 MPa (230,000 to 550,000 psi.)
    dampingModulusPSI          => 10000,
    # Cf rod damping modulus.  I don't really understand this, but numbers different bigger from 10000 slow the integrator way down.  For the moment, since I don't know how to get the this number for the various leader and tippet materials, I am taking this value for those as well.
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
    gravity         => 1,
        # Set to 1 to include effect of vertical gravity, 0 is no gravity, any value ok.
    dragSpecsNormal          => "11,-0.74,1.2",
    dragSpecsAxial           => "11,-0.74,0.01",
};


$rps->{driver} = {
	# Location of handle top, "X,Y,Z"
    startCoordsFt			=> "0.5,0,5",
    endCoordsFt				=> "1,0,4",
    pivotCoordsFt			=> "0,0,5",
	# Direction from handle bottom to handle top, actual length unused, "dX,dY,dZ".
    dirStartCoordsFt		=> "0,0,5",
	dirEndCoordsFt			=> "1,0,4",

    trackCurvatureInvFt     => 1/13,
    trackSkewness           => 0,   # Positive is more curved later.
    startTime               => 0,
    endTime                 => 0.5,
    velocitySkewness        => 0,   # Positive is faster later later.
    showTrackPlot           => 1,


    adjustEnable        => 1,
    frameRate           => 60,          # frames/sec.
    scale               => 1,
    rotate              => 0,           # Rad.  This will be eval'd.
    wristTheta          => 0,           # Rad, rel track base.  This will be eval'd.
    relRadius           => 0,           # Relative to normalized track base of 1.  0 for flat, or abs val bigger than 1/2 the track secant.  If abs larger than 10,000, resets to 0.  
    driveAccelFrames    => "20,10",  # frames.
    delayDriftFrames    => "5,20",   # frames.
    driveDriftTheta     => "0,0",       # rad.
    boxcarFrames        => "1",         # pos integer.
    plotSplines         => 0,
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

    releaseDelay     => 0.167,
        # How long after t0 to release the line tip.  -1 for before start of integration.
    releaseDuration  => 0.004,
        # Duration from start to end of release.

    debugVerbose    => 4,
    verbose         => 0,
};


# END CUT & PASTE DOCUMENTATION HERE =================================================


our %rCastRunControl = (
    callerUpdate        => sub {},
        # Called from the integration loop to allow the widget to operate.
    callerStop          => sub {},
        # Called on completion of the full integration.
    callerRunState      => 0,
    callerChangeVerbose	=> sub {},
);


# Package internal global variables ---------------------
#my $calculateAirDrag            = 0;
my ($dateTimeLong,$dateTimeShort,$runIdentifier);


#print Data::Dump::dump(\%rCastRunParams); print "\n";



# Package subroutines ------------------------------------------

sub RCastSetup {
    
    ## RHexCast is organized differently from RHexStatic.  Here, except for the preference file, files are not loaded when selected, but rather, loaded when run is called.  This lets the load functions use parameter settings to modify the load -- what you see (in the widget) is what you get.  In particular, widget value suggestions contained in the rod file are ignored.  Required non-widget values there (RodLength, Actionlength, NumSections, which are NOT widget parameters) are loaded.  This procedure allows the preference file to dominate.  Suggestions in the rod files should indicate details of that particular rod construction, which the user can bring over into the widget via the preferences file or direct setting, as desired.
    
    ### WARNING: pdl's are passed by reference.  So if you want the behavior as in C's declaring an argument constant, you must use $xx->copy in the function body.  $xx->sever doesn't seem to do it!
    ### No, it's subtler than that.  In the subroutine you need to explicitly use .= to back propagate!
    ### Indeed, you seem to need .= to assign anything less than the whole thing, otherwise you just
    
    
    
    SmoothChar_Setup(100);
    
    $dateTimeLong = scalar(localtime);
    if ($verbose>=2){print "\n\n$dateTimeLong\n"}
    
    my($date,$time) = ShortDateTime;
    $dateTimeShort = sprintf("(%06d_%06d)",$date,$time);
    
    $runIdentifier = 'RUN'.$dateTimeLong;
    
    PrintSeparator("INITIALIZING RUN - $dateTimeLong");
    
    if ($verbose>=5){print Data::Dump::dump(\%rCastRunParams); print "\n"}
    
    
    my $ok = CheckParams();
    if (!$ok){print "ERROR: Bad params.  Cannot proceed.\n\n";return 0};
    
    if (!LoadRod($rps->{file}{rod})){$ok = 0};
    if (!LoadLine($rps->{file}{line})){$ok = 0};
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
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Number of rod segments must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 2 or $val > 15)){print "WARNING: $str = $val - Typical range is [2,15].\n"}
    
    $str = "segExponent"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val <= 0){$ok=0; print "ERROR: $str = $val - Seg exponent must be positive.\n"}
    elsif($verbose>=1 and ($val < 1 or $val > 2)){print "WARNING: $str = $val - Typical range is [1,2].\n"}
	
    $str = "buttDiamIn"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val <= 0){$ok=0; print "ERROR: $str = $val - Butt diameter must be positive.\n"}
    elsif($verbose>=1 and ($val < 0.250 or $val > 0.500)){print "WARNING: $str = $val - Typical range is [0.250,5.000].\n"}

    $str = "tipDiamIn"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val <= 0){$ok=0; print "ERROR: $str = $val - Tip diameter must be positive.\n"}
    elsif($verbose>=1 and ($val < 0.050 or $val > 0.150)){print "WARNING: $str = $val - Typical range is [0.050,0.150].\n"}

    $str = "rodLenFt"; $val = $rps->{rod}{$str};
	my $rodLenFt = $val;
    if ($val eq '' or $val <= 0){$ok=0; print "ERROR: $str = $val - Rod length must be positive.\n"}
    elsif($verbose>=1 and ($val < 6 or $val > 15)){print "WARNING: $str = $val - Typical range is [6,15].\n"}
	
    $str = "actionLenFt"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val >= $rodLenFt){$ok=0; print "ERROR: $str = $val - Action length must be less than rod length.\n"}
    elsif($verbose>=1 and (abs($rodLenFt-$val) < 0.5 or abs($rodLenFt-$val) > 2)){print "WARNING: $str = $val - Typical range is [0.5,2].\n"}
	
    $str = "numSections"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val <= 0 or $val-int($val)!= 0){$ok=0; print "ERROR: $str = $val - Number of sections must be a positive integer.\n"}
    elsif($verbose>=1 and ($val > 4)){print "WARNING: $str = $val - Typical range is [1,4].\n"}
	
    $str = "densityLbFt3"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val <= 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 40 or $val > 75)){print "WARNING: $str = $val - Typical range is [40,75].\n"}
    
    $str = "fiberGradient"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and $val > 10){print "WARNING: $str = $val - Typical range is [0,10].\n"}
    
    $str = "maxWallThicknessIn"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    if ($val eq '' or $val > 0){$ok=0; print "ERROR: $str = $val - Hollow core rods not yet implemented.\n"}
    #    elsif($verbose>=1 and $val > 0.375){print "WARNING: $str = $val - Zero is no restriction.  Typical range is [0,0.375].\n"}
    
    $str = "elasticModulusPSI"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val <= 0){$ok=0; print "ERROR: $str = $val - Elastic modulus must be positive.\n"}
    elsif($verbose>=1 and ($val < 1e6 or $val > 1e7)){print "WARNING: $str = $val - Typical range is [1e6,1e7].\n"}
    
    $str = "dampingModulusStretchPSI"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 0 or $val > 1e6)){print "WARNING: $str = $val - Typical range is [0,1000???].\n"}
    
    $str = "dampingModulusBendPSI"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 0 or $val > 1e6)){print "WARNING: $str = $val - Typical range is [0,1000???].\n"}
    
    $str = "ferruleKsMult"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and $val > 2){print "WARNING: $str = $val - Typical range is [0,2].\n"}
    
    $str = "vAndGMultiplier"; $val = $rps->{rod}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and $val > 0.02){print "WARNING: $str = $val - Typical range is [0,0.02].\n"}
	
    $str = "nomWtGrsPerFt"; $val = $rps->{line}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and $val > 10){print "WARNING: $str = $val - Typical range is [0,10].\n"}
    
    $str = "totalThetaDeg"; $val = eval($rps->{rod}{$str});
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Initial rod curvature must be non-negative.\n"}
    #    elsif($verbose>=1 and ($val < 0.5 or $val > 2)){print "junk\n"}
    #elsif($verbose>=1 and $val > $pi/4){print "junk1\n"}
    elsif($verbose>=1 and $val > 90){print "WARNING: $str = $val - 0 is straight, positive values start rod concave toward the initial line direction.  Typical range is [0,90"}
    
    $str = "angle0Deg"; $val = eval($rps->{line}{$str});
	if ($val eq '' or $val <= -180 or $val >= 180){$ok=0; print "ERROR: $str = $val - Initial line angle must be in the range (-180,180).\n"}
    if($verbose>=1 and ($val < -110 or $val > -70)){print "WARNING: $str = $val -90 is horizontal to the left, usual range is [-110,-70].\n"}
    
    $str = "curve0InvFt"; $val = eval($rps->{line}{$str});
    if($verbose>=1 and ($val < 0 or $val > 1/20)){print "WARNING: $str = $val - 0 is straight, positive is concave up.  Typical range is [0,1 over (2*total line length including leader].\n"}
    
    $str = "numSegs"; $val = $rps->{line}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Number of line segments must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 2 or $val > 15)){print "WARNING: $str = $val - Typical range is [2,15].\n"}
    
    $str = "segExponent"; $val = $rps->{line}{$str};
    if ($val eq '' or $val <= 0){$ok=0; print "ERROR: $str = $val - Seg exponent must be positive.\n"}
    elsif($verbose>=1 and ($val < 1 or $val > 2)){print "WARNING: $str = $val - Typical range is [1,2].\n"}
    
    $str = "coreDiameterIn"; $val = $rps->{line}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 0.01 or $val > 0.05)){print "WARNING: $str = $val - Typical range is [0.01,0.05].\n"}
    
    $str = "coreElasticModulusPSI"; $val = $rps->{line}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 1e5 or $val > 4e5)){print "WARNING: $str = $val - Typical range is [1e5,4e5].\n"}
    
    $str = "dampingModulusPSI"; $val = $rps->{line}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 0 or $val > 1e5)){print "WARNING: $str = $val - Typical range is [0,1e5].\n"}
    
    $str = "lenFt"; $val = $rps->{leader}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - leader length must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 5 or $val > 15)){print "WARNING: $str = $val - Typical range is [5,15].\n"}
    
    $str = "wtGrsPerFt"; $val = $rps->{leader}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - weights must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 5 or $val > 15)){print "WARNING: $str = $val - Typical range is [7,18].\n"}
    
    $str = "diamIn"; $val = $rps->{leader}{$str};
    if ($val eq '' or $val <= 0){$ok=0; print "ERROR: $str = $val - diams must be positive.\n"}
    elsif($verbose>=1 and ($val < 0.004 or $val > 0.020)){print "WARNING: $str = $val - Typical range is [0.004,0.020].\n"}
    
    $str = "lenFt"; $val = $rps->{tippet}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - lengths must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 2 or $val > 12)){print "WARNING: $str = $val - Typical range is [2,12].\n"}
    
    $str = "diamIn"; $val = $rps->{tippet}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - diams must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 0.004 or $val > 0.012)){print "WARNING: $str = $val - Typical range is [0.004,0.012].\n"}
    
    $str = "wtGr"; $val = $rps->{fly}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and $val > 926){print "WARNING: $str = $val - Kluge for testing, 2 oz = 926 grains.  Typical real fly range is [0,5]\n"}
    
    $str = "nomDiamIn"; $val = $rps->{fly}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Fly nom diam must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 0 or $val > 0.25)){print "WARNING: $str = $val - Typical range is [0.1,0.25].\n"}
    
    $str = "nomLenIn"; $val = $rps->{fly}{$str};
    if ($val eq '' or $val < 0){$ok=0; print "ERROR: $str = $val - Fly nom diam must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 0 or $val > 1)){print "WARNING: $str = $val - Typical range is [0.25,1].\n"}
    
    my ($tt,$a,$b,$c,$err);
    $str = "dragSpecsNormal";
    $tt = Str2Vect($rps->{ambient}{$str});
    if ($tt->nelem != 3) {
        $ok=0;
        print "ERROR: $str must be of the form MULT,POWER,MIN where the first two are greater than zero and the last is greater than or equal to zero.\n";
    } else {
        $a = $tt(0); $b = $tt(1); $c = $tt(2);
        if ($verbose>=1 and ($a<10 or $a>12 or $b<-0.78 or $b>-0.70 or $c<1.0 or $c>1.4)){print "WARNING: $str = $a,$b - Experimentally measured values are 11,-0.74,1.2.\n"}
    }
    
    $str = "dragSpecsAxial";
    $tt = Str2Vect($rps->{ambient}{$str});
    if ($tt->nelem != 3) {
        $ok=0;
        print "ERROR: $str must be of the form MULT,POWER,MIN where the first two are greater than zero and the last is greater than or equal to zero.\n";
    } else {
        $a = $tt(0); $b = $tt(1); $c = $tt(2);
        if ($verbose>=1 and ($a<10 or $a>12 or $b<-0.78 or $b>-0.70 or $c<0.01 or $c>1)){print "WARNING: $str = $a,$b - Experiments are unclear, try  11,-0.74,0.1.  The last value should be much less than the equivalent value in the normal spec.\n"}
    }

    
    my $runTime = $rps->{integration}{t1}-$rps->{integration}{t0};
    if ($runTime <= 0){
        $ok = 0;
        print "ERROR: Run time must be positive.  Check values of t0 and t1.\n";
    }

    $str = "plotDt"; $val = eval($rps->{integration}{$str});
    if ($val eq '' or $val <= 0){$ok=0; print "ERROR: $str = $val - Must be positive.\n"}

    $str = "releaseDuration"; $val = $rps->{integration}{$str};
    if ($val eq '' or $val <= 0){$ok=0; print "ERROR: $str = $val - Must be positive.\n"}
    elsif($verbose>=1 and ($val < 0.001 or $val > 0.05)){print "WARNING: $str = $val - Typical range is [0.001,0.05].\n"}
    
    $str = "verbose"; $val = $rps->{integration}{$str};
    if ($val eq '' or $val < 0 or ceil($val) != $val){$ok=0; print "ERROR: $str = $val - Must be a non-negative integer.\n"}
    elsif(DEBUG and $verbose>=1 and ($val > 6)){print "WARNING: $str = $val - Typical range is [0,6].  Higher values print more diagnostic material.\n"}
    elsif(!DEBUG and $verbose>=1 and ($val > 3)){print "WARNING: $str = $val - Unless compiled in DEBUG mode, effective range is [0,3].  Higher values (<= 3) print more diagnostic material.\n"}

    if (DEBUG){
        $str = "debugVerbose"; $val = $rps->{integration}{$str};
        if ($val eq '' or $val < 3 or ceil($val) != $val or $val < $verbose){$ok=0; print "ERROR: $str = $val - Must be an integer greater than 2 and must also be no less than verbose ($verbose).\n"}
        elsif(DEBUG and $verbose>=1 and ($val > 6)){print "WARNING: $str = $val - Typical range is [0,6].  Higher values print more diagnostic material.\n"}
        $debugVerbose = $val;   # Make sure the actual variable is set.  If !DEBUG, this was done in RHexSwing3D.
    }
    print "\$debugVerbose = $debugVerbose\n";
    #die;

    return $ok;
}


my $rodIdentifier;
my ($rodLenFt,$actionLenFt,$numSections);
my ($loadedRodDiams,$loadedThetas);
my ($loadedState,$loadedRodSegLens,$loadedLineSegLens,$loadedT0);
my ($dXs,$dYs,$dZs);

sub LoadRod {
    my ($rodFile) = @_;
    
    ## Process rodFile if defined, otherwise set thetas and diams from defaults.  However, if an integration state (and its corresponding rod and line segment lengths) is available, we will use them to initialize the integration dynamical variables, ignoring other initial location specifiers.  Next preferred, if the 3D rod offsets are present, use them to set the initial configuration.  Finally, use flex if present.

    PrintSeparator("Loading rod");

    my $ok = 1;

    ($loadedRodDiams,$loadedThetas,$loadedState,
     $loadedRodSegLens,$loadedLineSegLens,$loadedT0,
	 $dXs,$dYs,$dZs) = map {zeros(0)} (0..8);

    my $tNumRodNodes = 31;
        # Just temporary, big enough to give ok resolution for later splining.  Will be overwritten if rod is loaded.

    if ($rodFile) {

        $/ = undef;
        #        open INFILE, "< $rodFile" or die $!;
        open INFILE, "< $rodFile" or $ok = 0;
        if (!$ok){print $!;return 0}
        my $inData = <INFILE>;
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

        $actionLenFt     = GetValueFromDataString($inData,"ActionLength","first");
        if (!defined($actionLenFt)){$ok = 0; print "ERROR: Unable to find ActionLength in $rodFile.\n"}

        $numSections        = GetValueFromDataString($inData,"NumSections","first");
        if (!defined($numSections)){$numSections = 1; if ($verbose>=1){print "Warning: Unable to find NumSections in $rodFile.  Setting NumSections=1.\n"};}
        
 
        my $tActionLen = 12*$actionLenFt;     # I need it (in inches) here.

        # In order to achieve better reproducibility by avoiding spline fitting when possible, if calculational arrays are available, use them in preference to station data:
            
        # Try to extract a calculated taper (diams) from the file.  These are assumed to be uniformly spaced.
        $loadedRodDiams = GetMatFromDataString($inData,"Taper","last");

        if ($loadedRodDiams->isempty) {

            # Try to pull a x stations out of the file:
            my $statXs = GetMatFromDataString($inData,"X_station","first");

            if ($statXs->isempty){$ok = 0; print "Error:  If Taper data is not present in file, then X_station and Taper_station data must be there.\n"}

            # Look for the corresponding taper stations:
            my $statDiams = GetMatFromDataString($inData,"Taper_station","first");

            if ($statDiams->isempty){$ok = 0; print "Error: If Taper data is not present in file, then X_station and Taper_station data must be there.\n"}
            if ($statXs->nelem != $statDiams->nelem){$ok = 0; print "Error: X_station and Taper_station sizes must agree.\n"}

            # Use station data to set diams via spline interpolation.
            $loadedRodDiams = StationDataToDiams($statXs,$statDiams,$tActionLen,$tNumRodNodes);
            if ($verbose>=2){print "Diams set from station data.\n"}
        }


		my $gotOffsets = 0;
		
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
								pq($dXs,$dYs,$dZs,$loadedThetas);
						}
					} else {
						print "Found DX but not DY or DZ.  Cannot work from offsets.\n";
					}
				}	# end DX but no DZ.
			}	# end got DX.
			

			if (!$gotOffsets){	# Couldn't work with offsets, see if there is a flex array:

				$loadedThetas = GetMatFromDataString($inData,"Flex");
				if (!$loadedThetas->isempty and $verbose>=2){print "Thetas set from flex.\n"}
				
				# To avoid later confusion, get rid of any offsets we might have gotten:
				($dXs,$dYs,$dZs) = map {zeros(0)} (0..2);
			}
		} # end search for offset or flex
	
    } else {	# No rodFile specified

        $rodLenFt		= $rps->{rod}{rodLenFt};
        $actionLenFt	= $rps->{rod}{actionLenFt};
        $numSections	= $rps->{rod}{numSections};

        my $buttDiam	= $rps->{rod}{buttDiamIn};
        my $tipDiam		= $rps->{rod}{tipDiamIn};
		
        my $buttStr		= POSIX::floor(1000*$buttDiam);
        my $tipStr		= POSIX::floor(1000*$tipDiam);
       
        $rodIdentifier = "LinearTaper_".$rodLenFt."_".$buttStr."_".$tipStr;

        $loadedRodDiams = DefaultDiams($tNumRodNodes,$buttDiam,$tipDiam);
		pq($tNumRodNodes,$buttDiam,$tipDiam,$loadedRodDiams);
        if ($verbose>=2){print "Diams set from default.\n"}
    }
                                
    # If, after all this, there are still no thetas, use defaults:
    if ($loadedState->isempty and $loadedThetas->isempty) {
		
		my $totalThetaRad	= eval($rps->{rod}{totalThetaDeg})*$pi/180;
        $loadedThetas = DefaultThetas($tNumRodNodes,$totalThetaRad);
        if ($verbose>=2){print "Thetas set from default.\n"}
        if ($verbose>=3){pq($loadedThetas)}
    }
    
    if (!$ok){print "LoadRod DETECTED ERRORS.\n"}
	
    # Coming out of here, all loadedDiams and loadedThetas reflect UNIFORM nodal spacing.  Of course, loadedState might not, but that will be dealt with later.
    return $ok;
}



my $lineIdentifier;
my $leaderStr;
my $flyLineNomWtGrPerFt;
my ($leaderLenFt,$tippetLenFt);
my ($loadedLineLenFt,$loadedLineGrsPerFt,$loadedLineDiamsIn,$loadedLineElasticDiamsIn,$loadedLineElasticModsPSI,$loadedLineDampingDiamsIn,$loadedLineDampingModsPSI);
my ($leaderElasticModPSI,$leaderDampingModPSI,$tippetElasticModPSI,$tippetDampingModPSI);

#use Switch;

sub LoadLine { my $verbose = 1?$verbose:0;
    my ($lineFile) = @_;

    ## Process lineFile if defined, otherwise set line from defaults.
    
    PrintSeparator("Loading line");
    
    my $ok = 1;
    
    $flyLineNomWtGrPerFt    = $rps->{line}{nomWtGrsPerFt};
    $loadedLineGrsPerFt     = zeros(0);
    
    if ($lineFile) {

        #die "FIX ME -- deal with missing diams, mods\n";
        
        if ($verbose>=1){print "Data from $lineFile.\n"}
        
        $/ = undef;
        #        open INFILE, "< $lineFile" or die $!;
        open INFILE, "< $lineFile" or $ok = 0;
        if (!$ok){print $!;return 0}
        my $inData = <INFILE>;
        close INFILE;
        
        if ($inData =~ m/^Identifier:\t(\S*).*\n/mo)
        {$lineIdentifier = $1; }
		
        $rps->{line}{identifier} = $lineIdentifier;
        if ($verbose>=2){print "lineID = $lineIdentifier\n"}
        
        # Find the line with "NominalWt" having the desired value;
        my ($str,$rem);
        my $ii=0;
        while ($inData =~ m/^NominalWt:\t(-?\d*)\n/mo) {
            my $tWeight = $1;
            if ($tWeight == $flyLineNomWtGrPerFt) {
                $rem = $';
                
                $loadedLineGrsPerFt = GetMatFromDataString($rem,"Weights");
                if ($verbose>=3){print "loadedLGrPerFt=$loadedLineGrsPerFt\n"}
                
                $loadedLineDiamsIn = GetMatFromDataString($rem,"Diameters");
                if ($verbose>=3){print "loadedLDiamsIn=$loadedLineDiamsIn\n"}
                
                if ($loadedLineDiamsIn->isempty){
                    $loadedLineDiamsIn  = $rps->{line}{nomDiameterIn}*ones($loadedLineGrsPerFt);    # Segment diams
                }
                last;
            }
            $inData = $';
            $ii++;
            if ($ii>15){last;}
        }
        if ($loadedLineGrsPerFt->isempty){$ok = 0; print "ERROR: Failed to find line weight $flyLineNomWtGrPerFt in file $lineFile.\n\n"}
        
    }else{
        
        # Create a default uniform line array.  This can have any weight:
        $lineIdentifier = "Level";
        $rps->{line}{identifier} = $lineIdentifier;
        
        $loadedLineGrsPerFt = $rps->{line}{nomWtGrsPerFt}*ones(60);    # Segment wts (ie, at cg)
        $loadedLineDiamsIn  = $rps->{line}{nomDiameterIn}*ones(60);    # Segment diams        
    }
    
    # Temporary:
    $loadedLineElasticDiamsIn   = $rps->{line}{coreDiameterIn}*ones(60);
    $loadedLineElasticModsPSI   = $rps->{line}{coreElasticModulusPSI}*ones(60);
    
    $loadedLineDampingDiamsIn   = $loadedLineDiamsIn;   # Sic, at least for now.
    $loadedLineDampingModsPSI   = $rps->{line}{dampingModulusPSI}*ones(60);
    
    if ($verbose>=2){print "Level line constructed from parameters.\n"}
    if ($verbose>=5){pq($loadedLineGrsPerFt,$loadedLineDiamsIn,$loadedLineElasticDiamsIn,$loadedLineElasticModsPSI,$loadedLineDampingDiamsIn,$loadedLineDampingModsPSI)}
    

    my $elasticModPSI_Nylon = 2.1e5;
    #my $DampingModPSI_Dummy = 10000;
    my $DampingModPSI_Dummy = $rps->{line}{dampingModulusPSI};
    
    print "FIX THIS: the fluoro youngs mod and both damping mods are made up by me\n";
    
    
    # Prepend the leader:
    my ($leaderGrsPerFt,$leaderDiamsIn,$leaderElasticDiamsIn,$leaderElasticModsPSI,$leaderDampingDiamsIn,$leaderDampingModsPSI);
    
    $leaderStr      = $rps->{leader}{text};
    $leaderStr      = substr($leaderStr,9); # strip off "leader - "
 
    switch ($leaderStr) {
    
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
        else    {die "\n\nERROR:  Dectected unimplemented leader text ($leaderStr).\n\n"}
    }
 
    $leaderElasticModsPSI   = $leaderElasticModPSI*ones($leaderLenFt);
    $leaderDampingModsPSI   = $leaderDampingModPSI*ones($leaderLenFt);
    
    
    $loadedLineLenFt += $leaderLenFt;
    
    $loadedLineGrsPerFt         = $leaderGrsPerFt->glue(0,$loadedLineGrsPerFt);
    $loadedLineDiamsIn          = $leaderDiamsIn->glue(0,$loadedLineDiamsIn);
    $loadedLineElasticDiamsIn   = $leaderElasticDiamsIn->glue(0,$loadedLineElasticDiamsIn);
    $loadedLineElasticModsPSI   = $leaderElasticModsPSI->glue(0,$loadedLineElasticModsPSI);
    $loadedLineDampingDiamsIn   = $leaderDampingDiamsIn->glue(0,$loadedLineDampingDiamsIn);
    $loadedLineDampingModsPSI   = $leaderDampingModsPSI->glue(0,$loadedLineDampingModsPSI);
    
    if ($verbose>=4){pq($leaderGrsPerFt,$leaderDiamsIn,$leaderElasticDiamsIn,$leaderElasticModsPSI,$leaderDampingDiamsIn,$leaderDampingModsPSI)}
    
    
    # Prepend tippet:
    
    # http://www.flyfishamerica.com/content/fluorocarbon-vs-nylon
    # The actual blend of polymers used to produce “nylon” varies somewhat, but the nylon formulations used to make monofilament leaders and tippets generally have a specific gravity in the range of 1.05 to 1.10, making them just slightly heavier than water. To put those numbers in perspective, tungsten—used in high-density sink tips—has a specific gravity of 19.25.
    # Fluorocarbon has a specific gravity in the range of 1.75 to 1.90. Tungsten (19.25) it ain’t,
    
    # From https://www.engineeringtoolbox.com/young-modulus-d_417.html, GPa2PSI = 144,928. Youngs Mod of Nylon 6  is in the range 2-4 GPa, giving 3-6e5.   http://www.markedbyteachers.com/as-and-a-level/science/young-s-modulus-of-nylon.html puts it at 1.22 to 1.98 GPa in the region of elasticity, so say 1.5GPa = 2.1e5 PSI.  For Fluoro, see https://flyguys.net/fishing-information/still-water-fly-fishing/the-fluorocarbon-myth for other refs.
    
    
    $tippetLenFt = POSIX::floor($rps->{tippet}{lenFt});
    my $specGravity;
    my $tippetStr = $rps->{line}{text};
    $tippetStr           = substr($tippetStr,9); # strip off "tippet - "
    
    switch ($tippetStr) {
        case "mono"     {$specGravity = 1.1; $tippetElasticModPSI = $elasticModPSI_Nylon; $tippetDampingModPSI = $DampingModPSI_Dummy}
        case "fluoro"   {$specGravity = 1.85; $tippetElasticModPSI = 4e5; $tippetDampingModPSI = $DampingModPSI_Dummy;}
    }
    
    
    my $tippetDiamsIn   = $rps->{tippet}{diamIn}*ones($tippetLenFt);
    #pq($tippetLenFt,$tippetDiamsIn);
    
    my $tippetVolsIn3           = 12*($pi/4)*$tippetDiamsIn**2;
    my $tippetGrsPerFt          =
    $specGravity * $waterOzPerIn3 * $grPerOz * $tippetVolsIn3 * ones($tippetLenFt);
    my $tippetElasticDiamsIn    = $tippetDiamsIn;
    my $tippetDampingDiamsIn    = $tippetDiamsIn;
    
    my $tippetElasticModsPSI    = $tippetElasticModPSI*ones($tippetLenFt);
    my $tippetDampingModsPSI    = $tippetDampingModPSI*ones($tippetLenFt);
    
    
    $loadedLineGrsPerFt = $tippetGrsPerFt->glue(0,$loadedLineGrsPerFt);
    $loadedLineDiamsIn = $tippetDiamsIn->glue(0,$loadedLineDiamsIn);
    
    $loadedLineLenFt += $tippetLenFt;
    
    $loadedLineGrsPerFt         = $tippetGrsPerFt->glue(0,$loadedLineGrsPerFt);
    $loadedLineDiamsIn          = $tippetDiamsIn->glue(0,$loadedLineDiamsIn);
    $loadedLineElasticDiamsIn   = $tippetElasticDiamsIn->glue(0,$loadedLineElasticDiamsIn);
    $loadedLineElasticModsPSI   = $tippetElasticModsPSI->glue(0,$loadedLineElasticModsPSI);
    $loadedLineDampingDiamsIn   = $tippetDampingDiamsIn->glue(0,$loadedLineDampingDiamsIn);
    $loadedLineDampingModsPSI   = $tippetDampingModsPSI->glue(0,$loadedLineDampingModsPSI);
    
    if ($verbose>=2){print "Level tippet constructed from parameters.\n"}
    if ($verbose>=4){pq($tippetGrsPerFt,$tippetDiamsIn,$tippetElasticDiamsIn,$tippetElasticModsPSI,$tippetDampingDiamsIn,$tippetDampingModsPSI)}
    
    if ($verbose>=3){pq($loadedLineGrsPerFt,$loadedLineDiamsIn,$loadedLineElasticDiamsIn,$loadedLineElasticModsPSI,$loadedLineDampingDiamsIn,$loadedLineDampingModsPSI)}
    

    if (!$ok){print "LoadLine DETECTED ERRORS.\n"}
    
    return $ok;
}



my $driverIdentifier;
my $numDriverTimes = 21;
my $driverSmoothingFraction = 0.2;
my ($driverStartTime,$driverEndTime);
my ($driverXs,$driverYs,$driverZs);
my ($driverDXs,$driverDYs,$driverDZs);


my ($timeXs,$timeYs,$timeZs,$timeThetas);  # pdls.

sub LoadDriver { my $verbose = 1?$verbose:0;
    my ($driverFile) = @_;

    my $ok = 1;
    ## Process driverFile if defined, otherwise set directly from driver params --------

    # Unset driver pdls (to empty rather than undef):
    ($driverXs,$driverYs,$driverZs,$driverDXs,$driverDYs,$driverDZs,$timeXs,$timeYs,$timeZs) =
        map {zeros(0)} (0..8);
                

    # The cast drawing is expected to be in SVG.  See http://www.w3.org/TR/SVG/ for the full protocol.  SVG does 2-DIMENSIONAL drawing only! See the function SVG_matrix() below for the details.  Ditto resplines.
    
    PrintSeparator("Loading cast driver");

    if ($driverFile) {
    
        if ($verbose>=2){print "Data from $driverFile.\n"}        

        $/ = undef;
        #        open INFILE, "< $driverFile" or die $!;
        open INFILE, "< $driverFile" or $ok = 0;
        if (!$ok){print $!;goto BAD_RETURN}
        my $inData = <INFILE>;
        close INFILE;
        
        my ($name,$dir,$ext) = fileparse($driverFile,'\..*');
        $driverIdentifier = $name;
        if ($verbose>=4){pq($driverIdentifier)}
        
        if ($ext eq ".svg"){
            # Look for the "CastSplines" identifier in the file:
            if ($inData =~ m[XPath]){
                if (!LoadDriverFromPathSVG($inData)){$ok=0;goto BAD_RETURN};
            } else {
                if (!LoadDriverFromHandleVectorsSVG($inData)){$ok=0;goto BAD_RETURN}
            }
        } else {  print "ERROR: Cast driver file must have .svg extension"; return 0}
                
    } else {
        if ($verbose>=2){print "No file.  Setting cast driver from params.\n"}
		SetDriverFromParams();
        #SetCastFromParams();
        $driverIdentifier = "Parameterized";
    }

if(0){
    # A base track is now in place.  Apply further curvature and theta adjustments as desired:
    if ($rps->{track}{adjustEnable}) {
        AdjustDriver();
    }
}
    
BAD_RETURN:
    if (!$ok){print "LoadDriver DETECTED ERRORS.\n"}

    return $ok;
}


=begin comment

sub AdjustDriver {

	die "Not implemented.\nStopped";
	

    ## If base track is to be rotated or curved, make that adjustment here.  Depends on my convention that tracks always start at (0,0).

    my $tScale  = Str2Vect($rps->{driver}{scale});
    #    my $scale = $rps->{driver}{scale};
    
    my $scale = $tScale(0);
    if ($scale != 1){
        $castXs *= $scale;
        $castYs *= $scale;

#print "SCALED:\n\tcastXs=$castXs\n\tcastYs=$castYs\n\tcastThetas=$castThetas\n";
    }
    
    if ($tScale->nelem > 1){
        my $rotScale = $tScale(1);
        $castThetas = $castThetas(0)+$rotScale*$castThetas;
    }

    my $rotTheta = eval($rps->{driver}{rotate});
    if ($rotTheta){
    
        my $tMat = $castXs->glue(1,$castYs);
        my $rotMat = pdl(cos($rotTheta),sin($rotTheta),-sin($rotTheta),cos($rotTheta))->reshape(2,2);
        $tMat = $rotMat x $tMat;

        $castXs = $tMat(:,0)->flat;
        $castYs = $tMat(:,1)->flat;
        $castThetas += $rotTheta;

#print "ROTATED:\n\tcastXs=$castXs\n\tcastYs=$castYs\n\tcastThetas=$castThetas\n";
    }
    
    my $relRad = $rps->{driver}{relRadius};
    if ($relRad) {
    
        # Implement convention that rad 0 is no op, and very large (say 10,000) abs is same as zero:
        if (abs($relRad) >= 10000) {$relRad = 0}
        CurveTrackBase($relRad);
    }
	
}

my ($castXs,$castYs,$castThetas);	# No longer used.


sub CurveTrackBase {
    my ($relRad) = @_;
    
    ## If base track is to be rotated or curved, make that adjustment now.  Depends on my convention that tracks always start at (0,0).  As usual, I base my angles on the upward pointing unit vector, increasing clockwise.
    
    ## A rightward pointing base vector bows concave down with positive relRad, concave up with negative.  The calculation below is Euclidean geometry:  all angles and all line segment lengths are positive.
    
    my $radSign = $relRad <=> 0;
    if ($radSign == 0) {return}
#pq $radSign;
    
    $relRad = abs($relRad);
    if ($relRad <= 0.5) {die "Absolute value of relRadius must be greater than 1/2.\n"}
    
    my $vCasts = $castXs->glue(1,$castYs)->transpose;
#pq $vCasts;

    # Find center of curvature:
    my $vTrack      = pdl($castXs(-1),$castYs(-1))->flat;
#pq $vTrack;
    my $trackLen    = sqrt($vTrack(0)**2+$vTrack(1)**2);
    my $radius      = $relRad*$trackLen;    
    
    # The positive angle between the track and the initial radius vector:
    my $theta   = acos($trackLen/(2*$radius));
    my $normLen = $radius*sin($theta);
#pq $normLen;
    
    my $vNorm   = pdl($vTrack(1),-$vTrack(0))->flat/$trackLen;
    my $cCurv   = $vTrack/2 + $normLen*$vNorm;
#pq $cCurv;
    
    # Compute (absolute) radial angles:
    my $vRad0   = -$cCurv;
    my $vRads   = $vCasts - $cCurv;
#pq vRads;
    my $tLen    = sqrt($vRads(0,0)**2+$vRads(1,0)**2);
#pq $tLen;

    my $radXs   = $vRads(0,:)->flat;
    my $radYs   = $vRads(1,:)->flat;
    my $radLens   = sqrt($radXs**2+$radYs**2);
    
    $radXs /= $radLens;
    $radYs /= $radLens;

    # The positive angles relative to the initial radius vector:
    my $phis    = atan2($radXs,$radYs);
#pq $phis\n";
    $phis       -= $phis(0)->sclr;     # Relative angles.
#pq $phis\n";
    $phis       = abs($phis);   # Made positive.
#pq $phis\n";
    
    # Compute the required radii increments:
    my $tanPhis     = tan($phis);
    my $tanTheta    = tan($theta);
    my $ws      = $tanTheta/($tanPhis+$tanTheta);
#pq $ws\n";
    my $cs      = $radius*$ws/cos($phis);
#pq $cs\n";
    
    my $radIncrs = $radSign*($radius-$cs);
#pq $radIncrs\n";
        
    # Convert the increments to vectors and add to the cast vects:
    $castXs += $radIncrs*$radXs;
    $castYs += $radIncrs*$radYs;
#pq($castXs,$castYs);
    
    # Adjust the cast thetas.  A radius vector to the middle of the track yields no change:
    my $phiHalf     = $pi/2 - $theta;
    $castThetas     += $phis-$phiHalf;
#pq $castThetas;
}

=end comment

=cut



sub SetDriverFromParams {
	
    ## If driver was not already read from a file, construct a normalized one on a linear base here from the widget's track params:
    
    my $curvature   = eval($rps->{driver}{trackCurvatureInvFt})/12;
        # 1/Inches.  Positive curvature is away from the pivot.

    my $coordsStart = Str2Vect($rps->{driver}{startCoordsFt})*12;        # Inches.
    my $coordsEnd   = Str2Vect($rps->{driver}{endCoordsFt})*12;
    my $coordsPivot = Str2Vect($rps->{driver}{pivotCoordsFt})*12;
	
    my $length	= sqrt(sum(($coordsEnd - $coordsStart)**2));

	my $dirsStartUnit	= Str2Vect($rps->{driver}{dirStartCoordsFt});
	my $dirsEndUnit		= Str2Vect($rps->{driver}{dirEndCoordsFt});
	pq($dirsStartUnit,$dirsEndUnit);
	
	$dirsStartUnit	/= sqrt(sum($dirsStartUnit**2));
	$dirsEndUnit	/= sqrt(sum($dirsEndUnit**2));
    my $dirsDiffLen		= sqrt(sum(($dirsEndUnit - $dirsStartUnit)**2));
	pq($dirsStartUnit,$dirsEndUnit,$dirsDiffLen);
	
	
    $driverStartTime    = $rps->{driver}{startTime};
    $driverEndTime      = $rps->{driver}{endTime};
    if ($verbose>=3){pq($driverStartTime,$driverEndTime)}
	
    if ($driverStartTime >= $driverEndTime or ($length == 0 and $dirsDiffLen == 0)){  # No handle motion
        
        ($driverXs,$driverYs,$driverZs) = map {ones(2)*$coordsStart($_)} (0..2);
		($timeXs,$timeYs,$timeZs)       = map {sequence(2)} (0..2);     # KLUGE:  Spline interpolation requires at least 2 distinct time values.
		
        ($driverDXs,$driverDYs,$driverDZs)	= map {ones(2)*$dirsStartUnit($_)} (0..2);
		pq($driverDXs,$driverDYs,$driverDZs);

    } else {
    
		my $totalTime	= $driverEndTime-$driverStartTime;
		my $times		= $driverStartTime +
							sequence($numDriverTimes)*$totalTime/($numDriverTimes-1);
		
		my $tFracts     = sequence($numDriverTimes+1)/($numDriverTimes);
		my $tMultStart  = 1-SmoothChar($tFracts,0,$driverSmoothingFraction);
		my $tMultStop   = SmoothChar($tFracts,1-$driverSmoothingFraction,1);
		
		my $slopes  = $tMultStart*$tMultStop;
		my $vals    = cumusumover($slopes(0:-2));
		$vals   /= $vals(-1);
		
		my $coords = $coordsStart + $vals->transpose*($coordsEnd-$coordsStart);
		
		#my $plotCoords = $times->transpose->glue(0,$coords);
		#PlotMat($plotCoords);
		
		if ($length and $curvature){
			#pq($coords);
			# Get vector in the plane of the track ends and the pivot that is perpendicular to the track and pointing away from the pivot.  Do this by projecting the pivot-to-track start vector onto the track, and subtracting that from the original vector:
			my $refVect     = $coordsStart - $coordsPivot;
			my $unitTrack   = $coordsEnd - $coordsStart;
			$unitTrack      /= sqrt(sum($unitTrack**2));
			
			my $unitDisplacement    = $refVect - sum($refVect*$unitTrack)*$unitTrack;
			$unitDisplacement      /= sqrt(sum($unitDisplacement**2));

			#pq($length,$curvature,$refVect,$unitTrack,$unitDisplacement);
			
			my $xs  = sqrt(sumover(($coords-$coordsStart)**2));   # Turned into a flat vector.
			
			my $skewExponent = $rps->{driver}{trackSkewness};
			if ($skewExponent){
				$xs = SkewSequence(0,$length,$skewExponent,$xs);
			}
			
			my $secantOffsets = SecantOffsets(1/$curvature,$length,$xs);     # Returns a flat vector.
			
			$coords += $secantOffsets->transpose x $unitDisplacement;
		}

		
		($driverXs,$driverYs,$driverZs)   = map {$coords($_,:)->flat} (0..2);
		pq($coords);
		pq($driverXs,$driverYs,$driverZs);

		
		pq($vals);
		my $dirsUnit	= $dirsStartUnit + $vals->transpose*($dirsEndUnit-$dirsStartUnit);
		pq($dirsUnit);
		my $denoms = sqrt(sumover($dirsUnit**2))->transpose;
		pq($denoms);
		$dirsUnit		/= $denoms;
		($driverDXs,$driverDYs,$driverDZs)	= map {$dirsUnit($_,:)->flat} (0..2);
		pq($dirsUnit);
		pq($driverDXs,$driverDYs,$driverDZs);
		
		
		my $velExponent = $rps->{driver}{velocitySkewness};
		if ($velExponent){
			#pq($times);
			$times = SkewSequence($driverStartTime,$driverEndTime,-$velExponent,$times);
			# Want positive to mean fast later.
		}
		
		
		$timeXs = $times;
		$timeYs = $times;
		$timeZs = $times;
	}
	
    if ($rps->{driver}{showTrackPlot}){
        my %opts = (gnuplot=>$gnuplot,xlabel=>"x-axis (ft)",ylabel=>"y-axis (ft)",zlabel=>"z-axis (ft)");

        Plot3D($driverXs/12,$driverYs/12,$driverZs/12,"Handle Top Track",\%opts);
        Plot3D($driverDXs,$driverDYs,$driverDZs,"Toward handle top",pdl(0),pdl(0),pdl(0),"Handle bottom","Handle Directions Track",\%opts);
    }
}


=begin comment

sub SetCastFromParams {


    ## If cast was not already read from a file, construct a normalized one on a linear base here from the widget's track params:

    my $driveAccelFrames    = Str2Vect($rps->{driver}{driveAccelFrames});
    my $delayDriftFrames    = Str2Vect($rps->{driver}{delayDriftFrames});
    my $driveDriftTheta     = Str2Vect($rps->{driver}{driveDriftTheta});


    my $driveFrames     = $driveAccelFrames(0)->sclr;
    my $accelFrames     = $driveAccelFrames(1)->sclr;
    my $delayFrames     = $delayDriftFrames(0)->sclr;
    my $driftFrames     = $delayDriftFrames(1)->sclr;

    my $driveTheta      = $driveDriftTheta(0)->sclr;
    my $driftTheta      = $driveDriftTheta(1)->sclr;

    my $totalFrames = $driveFrames + $delayFrames + $driftFrames;
    
    $castYs = zeros($totalFrames);
    $castXs = ones($totalFrames);

    if ($accelFrames < 1 or $accelFrames > $driveFrames-1){
        die "AccelFrames must be positive and strictly less than driveFrames.\n";
    }
    my $decelFrames = $driveFrames - $accelFrames + 1;
    
    my $aXs = sequence($accelFrames);
    $aXs    = $aXs*$aXs;
    my $dXs = sequence($decelFrames);
    $dXs    = $dXs*$dXs*($decelFrames/$accelFrames);
    $dXs    = $aXs(-1)+$dXs(-1)-$dXs(-2:0);
    
    my $driveXs = $aXs->glue(0,$dXs);
    $driveXs = $driveXs/$driveXs(-1);
    
    $castXs(0:$driveFrames-1) .= $driveXs;
    
    if ($verbose>=1){print " accelFrames=$accelFrames,decelFrames=$decelFrames\naXs=$aXs\ndXs=$dXs\n"}

    my $driveThetas = $driveXs*$driveTheta;
    my $delayThetas = ones($delayFrames)*$driveTheta;
            
    my $driftThetas = zeros(0);
    if ($driftFrames){
        $driftThetas = sequence($driftFrames+1)*$driftTheta/$driftFrames;
        $driftThetas = $driftThetas(1:-1)+$driveTheta;
    }    
    if ($verbose>=3){pq($driveThetas,$delayThetas,$driftThetas)}

    $castThetas = $driveThetas->glue(0,$delayThetas)->glue(0,$driftThetas);
    if ($verbose>=3){pq($castXs,$castYs,$castThetas)}

    # Total driven time ~ dist/4*maxV.    driftDelay      => 0.2, 

}

=end comment

=cut


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



sub LoadDriverFromPathSVG {
    my ($inData) = @_;
    
    ## These casts are heirloom, and take place entirely in the vertical plane.  This function depends on my very specific requirements for constructing paths from (re)splined plots.  Read the other way, it says what those conditions are.  Switched old 2D y-dim for new 3D z-dim.

#pq $inData;

    if ($verbose>=3){print "Loading cast driver from path svg...\n"}
    
    my $timeScale;
    my $valueScale;
    my $thetaMult;
	my $driverThetas;
    
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
	
	$driverYs	= zeros($driverXs);
	$driverDYs	= zeros($driverXs);
    
    if ($verbose>=3){pq($timeXs,$driverXs,$timeYs,$driverYs,$timeThetas,$driverThetas)}
}



sub LoadDriverFromHandleVectorsSVG {
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
    	my $coordsStart = Str2Vect($rps->{driver}{startCoordsFt})*12;        # Inches.
		$driverXs += $coordsStart(0);
		$driverYs += $coordsStart(1);
		$driverZs += $coordsStart(2);
	}
	
	# There are no times in this formulation.  Set them from the params:
	$driverStartTime    = $rps->{driver}{startTime};
    $driverEndTime      = $rps->{driver}{endTime};
    if ($verbose>=3){pq($driverStartTime,$driverEndTime)}
	
	my $numTimes = $driverXs->nelem;
	my $times;
    if ($driverStartTime >= $driverEndTime){  # No handle motion
        
		$times = sequence(2);	# KLUGE:  Spline interpolation requires at least 2 distinct time values.
	} else {

		my $totalTime	= $driverEndTime-$driverStartTime;
		$times			= $driverStartTime +
							sequence($numTimes)*$totalTime/($numTimes-1);
	}

	($timeXs,$timeYs,$timeZs)	= map {$times} (0..2);
	
    if ($verbose>=3) {pq($driverXs,$driverYs,$driverZs,$driverDXs,$driverDYs,$driverDZs,$times)}

    return 1;
}    



# Variables loaded by SetupModel():
my ($g,$rodLen,$actionLen,$handleLen);
my ($numRodNodes,$rodNodeDiams,$rodThetas);
my ($numRodSegs,$rodSegLens,$rodStretchKs,$rodStretchCs,$rodTorqueKs,$rodTorqueCs);

my ($flyNomLen,$flyNomDiam,$flyWt);
my ($activeLenFt,$activeLen);   # Total loop length, outside of rod tip, including leader and tippet.
my ($numLineSegs,$lineSegNomLens,$lineSegKs,$lineSegCs);

my ($numSegs,$segWts,$segLens,$segCGs,$segCGDiams,$segKs,$segCs);
my ($outStr,$paramsStr);

my ($lineTipOffset,$leaderTipOffset);


sub SetupModel { my $verbose = 1?$verbose:0;

    ## Called just prior to running. Convert the rod and line file data to a specific model for use by the integrator.  Note that this function does not deal with initial rod or line configuration, but just with its physical properties.
    
    PrintSeparator("Setting up model");

    # Deal with parameters that need units conversion or for which it is convenient to have renamed globals:
    $g  = $rps->{ambient}{gravity};
    
    # Setup rod -----------------------

    $rodThetas = zeros(0);

    # See if state, and then, necessarily, rod and line segs, were loaded:
    if ($loadedState->isempty){

        $numRodSegs     = $rps->{rod}{numSegs};
        $numRodNodes    = $numRodSegs+1;
        $rodSegLens     = zeros(0);

        $numLineSegs    = $rps->{line}{numSegs};
        $lineSegNomLens = zeros(0);
            # Nominal because we will later deal with stretch.

    } else{

        $numRodSegs     		= $loadedRodSegLens->nelem;
        $numRodNodes    		= $numRodSegs+1;
        $rps->{rod}{numSegs}	= $numRodSegs;   # Show the user.
        $rodSegLens     		= $loadedRodSegLens;
        
        $numLineSegs   			= $loadedLineSegLens->nelem;
        $rps->{line}{numSegs}	= $numLineSegs;   # Show the user.
        $lineSegNomLens 		= $loadedLineSegLens;
    }
    
    my ($rodSegWts,$rodSegMoments,$rodSegCGs,$rodSegDiams);
    my ($totalRodActionWt);
    $numSegs = $numRodSegs + $numLineSegs;

    if ($numRodSegs){
        
        # Convert to ounces and inches where necessary:
        $rodLen		= $rodLenFt * 12;
        $actionLen	= $actionLenFt * 12;
        $handleLen	= $rodLen - $actionLen;

        my $rodDensity          = $rps->{rod}{densityLbFt3} * 16 / 12**3;
        my $rodElasticModulus   = $rps->{rod}{elasticModulusPSI} * 16;
        my $rodDampModStretch   = $rps->{rod}{dampingModulusStretchPSI} * 16;
        my $rodDampModBend		= $rps->{rod}{dampingModulusBendPSI} * 16;
        my $fiberGradient       = $rps->{rod}{fiberGradient};
        my $maxWallThickness    = $rps->{rod}{maxWallThicknessIn};
        my $ferruleKsMult       = $rps->{rod}{ferruleKsMult};
        my $vAndGMultiplier     = $rps->{rod}{vAndGMultiplier};

        
        #if (!$rodSegLens->isempty){
        if ($rodSegLens->isempty){ # Otherwise all this was loaded.

            # Set up the rod segment lengths.  These are in inches:
            my $rodNodeLocs = sequence($numRodNodes)**$rps->{rod}{segExponent};

            $rodNodeLocs *= $actionLen/$rodNodeLocs(-1);
            if ($verbose>=1){print "rodNodeLocs=$rodNodeLocs\n"}
            
            $rodSegLens = $rodNodeLocs(1:-1)-$rodNodeLocs(0:-2);
            $rodSegLens = $rodSegLens(-1:0);
                # Want the short segments at the tip.
        }

        if ($verbose>=2){pq $rodSegLens}
        
        my $rodNodeRelLocs = cumusumover(zeros(1)->glue(0,$rodSegLens));
        $rodNodeRelLocs /= $rodNodeRelLocs(-1);    
        if ($verbose>=3){pq $rodNodeRelLocs}
           
        my $rodNodeDiams = ResampleVectLin($loadedRodDiams,$rodNodeRelLocs);
        if ($verbose>=2){pq $rodNodeDiams}
        
        # Figure effective nodal diam second moments (adjusted for power fiber distribution).  Uses the diameter at the segment lower end:
		#pq($maxWallThickness);
        my $effectiveSect2ndMoments = GradedSections($rodNodeDiams,$fiberGradient,$maxWallThickness);
        if ($verbose>=4){pq($effectiveSect2ndMoments)}

		#  Compute hinge spring torques (adjusted for additional ferrule stiffness).  Need to know the seg lens to deal with the ferrules.
		my $rodKs = RodKs($rodSegLens,$effectiveSect2ndMoments,$rodElasticModulus,
                            $ferruleKsMult,$handleLen,$numSections);
		
		# These are the spring constants in bending that gives the restoring force supposing the segs are each unit length.  The pDots code in RHamilton3D will insert the correct momentary lever arm to get the generalized force (ie, the tangential cartesian force acting at the segment outboard end):
		$rodTorqueKs	= $rodKs*$rodSegLens;
		
        # Use the same second moments as for K's:
        $rodTorqueCs = ($rodDampModBend/$rodElasticModulus)*$rodTorqueKs;
        # Presumes that internal friction arises from power fiber configuration in the same way that bending elasticity does.  The relative local bits of motion cause a local drag tension (compression), but the ultimate force on the mass is just the same as the local ones (all equal if uniform velocity strain. I have no independent information about the appropriate value for the damping modulus.  Running the simulation, small values lead to complete distruction of the rod.  Values nearly equal to the elastic modulus give seemingly appropriate rod tip damping.  For the moment, I'll let the dampingModulus eat any constant factors.
        if ($verbose>=2){pq($rodTorqueKs,$rodTorqueCs)}

        $rodSegDiams = ($rodNodeDiams(0:-2)+$rodNodeDiams(1:-1))/2;
        # Correct average value over the segment, and appropriate for use with air drags.

        # When stretching, just the diameter counts, and the average segment diameter ought to be better than the lower end diameter:
		my $stretchMults = $hexAreaFactor*$rodSegDiams**2/$rodSegLens;
		
        $rodStretchKs = $rodElasticModulus*$stretchMults;
        $rodStretchCs = $rodDampModStretch*$stretchMults;
		pq($rodStretchKs,$rodStretchCs);

        # Figure segment weights and relative cgs for inertial torques:
        my ($segBambooWts,$segBambooMoments) =
            RodSegWeights($rodSegLens,$rodNodeDiams,$rodDensity,
                            $fiberGradient,$maxWallThickness);

        my $lineNomWeight   = $flyLineNomWtGrPerFt / (12*437.5);
        
        my ($segExtraWts,$segExtraMoments) =
            RodSegExtraWeights($rodSegLens,$rodNodeDiams,$vAndGMultiplier,
                                $lineNomWeight,$handleLen,$numSections);
        
        $rodSegWts      = $segBambooWts + $segExtraWts;
        $rodSegMoments  = $segBambooMoments + $segExtraMoments;
        
        $rodSegCGs  = $rodSegMoments/$rodSegWts;
        
        $totalRodActionWt = sumover($rodSegWts);
        
    }

    # Setup line --------------------
    
    my ($lineSegLens,$lineSegCGs,$lineSegCGDiams,$lineSegWts);
	
    if ($numLineSegs) {
        
        $paramsStr .= "Line: $lineIdentifier\n";

        my $lineLenFt   = $rps->{line}{activeLenFt};
        if ($verbose>=3){pq($lineLenFt,$leaderLenFt,$tippetLenFt)}
        
        $leaderTipOffset    = $tippetLenFt*12;  # inches
        $lineTipOffset      = $leaderTipOffset + $leaderLenFt*12;
        
        pq($lineTipOffset,$leaderTipOffset);

        $activeLenFt = $lineLenFt + $leaderLenFt + $tippetLenFt;
        $activeLen   = $activeLenFt * 12;
        if ($verbose>=3){pq($activeLen)}
        
        my $fractNodeLocs;
        if ($lineSegNomLens->isempty) {
            $fractNodeLocs = sequence($numLineSegs+1)**$rps->{line}{segExponent};
        } else {
            $fractNodeLocs = cumusumover(zeros(1)->glue(0,$lineSegNomLens));
        }
        $fractNodeLocs /= $fractNodeLocs(-1);
       
        my $nodeLocs        = $activeLen*$fractNodeLocs;
        if ($verbose>=3){pq($fractNodeLocs,$nodeLocs)}
        
        # Figure the segment weights -------
        
        # Take just the active part of the line, leader, tippet.  Low index is TIP:
        my $lastFt  = POSIX::floor($activeLenFt);
        #pq ($lastFt,$totalActiveLenFt,$loadedLineGrsPerFt);
        
        my $availFt = $loadedLineGrsPerFt->nelem;
        if ($lastFt >= $availFt){die "Active length (sum of line outside rod tip, leader, and tippet) requires more fly line than is available in file.  Set shorter active len or load a different line file.\n"}
        
        my $activeLineGrs =  $loadedLineGrsPerFt($lastFt:0)->copy;    # Re-index to start at rod tip.
        if ($verbose>=4){pq($activeLineGrs)}
        
        my $nodeGrs     = ResampleVectLin($activeLineGrs,$fractNodeLocs);
        
        my $denoms      = $nodeGrs(0:-2)+$nodeGrs(1:-1);
        $lineSegCGs     = $nodeGrs(1:-1)/$denoms;
        my $ok          = $denoms > 0;  # get rid of NaNs from weightless segs.
        $lineSegCGs         = $ok*$lineSegCGs + (1-$ok)*0.5;
        #pq($ok,$lineSegCGs);
        
        my $cumGrsNodes     = cumusumover(zeros(1)->glue(0,$activeLineGrs));
        my $cumGrsAtNodes   = ResampleVectLin($cumGrsNodes,$fractNodeLocs);
        my $segGrs          = $cumGrsAtNodes(1:-1)-$cumGrsAtNodes(0:-2);
        #pq $lineGrsSegs;
        
        $lineSegWts = $segGrs/$grPerOz;
        if ($verbose>=4){pq($lineSegCGs,$lineSegWts)}
        # Ounces attributed to each line segment.
        
        # Figure the seg lengths.
        $lineSegLens = $nodeLocs(1:-1)-$nodeLocs(0:-2);
        if ($lineSegNomLens->isempty){$lineSegNomLens = $lineSegLens}
        my $segCGLocs   = $nodeLocs(0:-2) + $lineSegCGs*$lineSegLens;
        
        pq($lineSegNomLens,$lineSegLens);
        
        my $fractCGLocs = $segCGLocs/$nodeLocs(-1);
        if ($verbose>=3){pq($lineSegLens,$lineSegCGs,$segCGLocs,$fractCGLocs)}
        
        my $activeDiamsIn =  $loadedLineDiamsIn($lastFt:0)->copy;    # Re-index to start at rod tip.
        $lineSegCGDiams = ResampleVectLin($activeDiamsIn,$fractCGLocs);
        # For the line I will compute Ks and Cs based on the diams at the segCGs.
        if ($verbose>=3){pq($lineSegCGDiams)}
        
        my $activeElasticDiamsIn =  $loadedLineElasticDiamsIn($lastFt:0);
        my $activeElasticModsPSI =  $loadedLineElasticModsPSI($lastFt:0);
        my $activeDampingDiamsIn =  $loadedLineDampingDiamsIn($lastFt:0);
        my $activeDampingModsPSI =  $loadedLineDampingModsPSI($lastFt:0);
        
        my $segCGElasticDiamsIn    = ResampleVectLin($activeElasticDiamsIn,$fractCGLocs);
        my $segCGElasticModsPSI    = ResampleVectLin($activeElasticModsPSI,$fractCGLocs);
        my $segCGDampingDiamsIn    = ResampleVectLin($activeDampingDiamsIn,$fractCGLocs);
        my $segCGDampingModsPSI    = ResampleVectLin($activeDampingModsPSI,$fractCGLocs);
        if ($verbose>=3){pq($segCGElasticDiamsIn,$segCGElasticModsPSI,$segCGDampingDiamsIn,$segCGDampingModsPSI)}
    
        # Build the active Ks and Cs:
        my $elasticCGAreas    = ($pi/4)*$segCGElasticDiamsIn**2;
        my $elasticCGMods     = $segCGElasticModsPSI * 16;    # Oz per sq in.
        
        $lineSegKs = $elasticCGMods*$elasticCGAreas/$lineSegLens;      # Oz to stretch 1 inch.
        # Basic Hook's law, on just the level core, which contributes most of the stretch resistance.
        
        my $dampingAreas    = ($pi/4)*$segCGDampingDiamsIn**2;
        my $dampingMods     = $segCGDampingModsPSI * 16;    # Oz per sq in.
        
        $lineSegCs = $dampingMods*$dampingAreas/$lineSegLens;  # Oz to stretch 1 inch.
        # By analogy with Hook's law, on the whole diameter. Figure the elongation damping coefficients USING FULL LINE DIAMETER since the plastic coating probably contributes significantly to the stretching friction.
        
        if ($verbose>=3){pq($lineSegKs,$lineSegCs)}
    }
    
    
    # Combine rod and line (including leader and tippet):
    $segWts     = $rodSegWts->glue(0,$lineSegWts);
    $segCGs     = $rodSegCGs->glue(0,$lineSegCGs);

    $segCGDiams = $rodSegDiams->glue(0,$lineSegCGDiams);
    $segLens    = $rodSegLens->glue(0,$lineSegLens);
    
    $segKs      = $rodStretchKs->glue(0,$lineSegKs);
    $segCs      = $rodStretchCs->glue(0,$lineSegCs);

    my $totalLineLoopWt = sum($segWts(-$numLineSegs,-1));

    if ($verbose>=3){print "\n";pq($totalRodActionWt,$totalLineLoopWt);print "\n"}
    
    # Set the fly specs:
    $flyWt          = eval($rps->{fly}{wtGr})/$grPerOz;
    $flyNomLen      = eval($rps->{fly}{nomLenIn});
    $flyNomDiam     = eval($rps->{fly}{nomDiamIn});
    if ($verbose>=3){pq($flyWt,$flyNomLen,$flyNomDiam)}
}



my ($driverXSpline,$driverYSpline,$driverZSpline,
    $driverDXSpline,$driverDYSpline,$driverDZSpline,
    $frameRate,$driverTotalTime,
    $tipReleaseStartTime,$tipReleaseEndTime,
    $driverStr);

sub SetupDriver { my $verbose = 1?$verbose:0;

    ## Prepare the external constraint at the handle that is applied during integration by Calc_Driver() in RHamilton3D.
    
    # In this function I convert to the new 3D driver format.
    
    PrintSeparator("Setting up handle driver");
	
    # Set up spline interpolations, so that during integration we can just eval.
    if (!defined($timeXs) or !$timeXs->nelem){   # Not loaded from PathSVG, so all the same:
        $frameRate  = $rps->{driver}{frameRate};
        $timeXs     = ($driverXs->sequence)/$frameRate;
        $timeYs     = $timeXs;  # no need to make copies.
        $timeZs     = $timeXs;
        if ($verbose>=4){pq $timeXs}

        my $bcFrames = POSIX::ceil($rps->{driver}{boxcarFrames});
        if ($bcFrames>1){
            $driverXs     = BoxcarVect($driverXs,$bcFrames);
            $driverYs     = BoxcarVect($driverYs,$bcFrames);
            $driverZs     = BoxcarVect($driverZs,$bcFrames);
            $driverDXs     = BoxcarVect($driverDXs,$bcFrames);
            $driverDYs     = BoxcarVect($driverDYs,$bcFrames);
            $driverDZs     = BoxcarVect($driverDZs,$bcFrames);
        }
    }

    pq($timeXs,$timeYs,$timeZs);
    
    my $tStarts = $timeXs(0)->glue(0,$timeYs(0))->glue(0,$timeZs(0));
    $driverStartTime = $tStarts->max;
	
    my $tEnds =
        $timeXs(-1)->glue(0,$timeYs(-1))->glue(0,$timeZs(-1));
        # If they came from resplining, they might be a tiny bit different.
    $driverEndTime = $tEnds->min;
    
    $driverTotalTime = $driverEndTime-$driverStartTime;        # Used globally.
    if ($verbose>=4){pq $driverTotalTime}

    # Interpolate in arrays, all I have for now:
    my @aTimeXs     = list($timeXs);
    my @aTimeYs     = list($timeYs);
    my @aTimeZs     = list($timeZs);
	
    my @aDriverXs = list($driverXs);
    my @aDriverYs = list($driverYs);
    my @aDriverZs = list($driverZs);
    
    my @aDriverDXs = list($driverDXs);
    my @aDriverDYs = list($driverDYs);
    my @aDriverDZs = list($driverDZs);
    
    $driverXSpline = Math::Spline->new(\@aTimeXs,\@aDriverXs);
    $driverYSpline = Math::Spline->new(\@aTimeYs,\@aDriverYs);
    $driverZSpline = Math::Spline->new(\@aTimeZs,\@aDriverZs);
    
    $driverDXSpline = Math::Spline->new(\@aTimeXs,\@aDriverDXs);
    $driverDYSpline = Math::Spline->new(\@aTimeYs,\@aDriverDYs);
    $driverDZSpline = Math::Spline->new(\@aTimeZs,\@aDriverDZs);
    
    # Plot the cast with enough points in each segment to show the spline behavior:
    if ($rps->{driver}{plotSplines}){
        my $numTs = 100;
        PlotHandleSpline($numTs,$driverXSpline,$driverYSpline,$driverZSpline,
        $driverDXSpline,$driverDYSpline,$driverDZSpline);  # To terminal only.
    }
    
    my $releaseDelay        = eval($rps->{integration}{releaseDelay});
    my $releaseDuration     = eval($rps->{integration}{releaseDuration});
    my $t0                  = eval($rps->{integration}{t0});
    
    if ($releaseDelay < 0) {
        # Turn off delay mechanism:
        $tipReleaseStartTime    = $t0 - 1;
        $tipReleaseEndTime      = $t0 - 0.5;
    } else {
        $tipReleaseStartTime    = $t0 + $releaseDelay;
        $tipReleaseEndTime      = $tipReleaseStartTime + $releaseDuration;
    }
   
    # Set driver string:    
    my $tTT = sprintf("%.3f",$driverTotalTime);
    my $tTRS = sprintf("%.3f",$tipReleaseStartTime);
    my $tTRE = sprintf("%.3f",$tipReleaseEndTime);
        
    $driverStr = "t=($rps->{integration}{t0}:$rps->{integration}{t1}:$rps->{integration}{plotDt}) $rps->{integration}{stepperName}\ndriven=(0,$tTT)\ntRelease=($tTRS,$tTRE)";

    if ($verbose>=2){pq $driverStr}
}




my ($eventTs,$iEvents);

sub SetEventTs { my $verbose = 1?$verbose:0;
    
    my ($t0,$tipReleaseStartTime,$tipReleaseEndTime) = @_;

    ## Set the times of the scheduled, typically irregular, events that mark a change in integrator behavior.
    
    # In the current implementation, hold, if any, must start at T0.
    
    if ($tipReleaseStartTime <= $t0) # Our indication that there is no holding.
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
	
	## Think right-handed x,y,z.  $theta0 = 0 points along the poistive z-axis, and increasing moves toward positve x.  $axialA = 0 poitns along the positive z-axis, and increasing moves toward positive y.  After figuring the offsets in the x-z plane, rotates around the x-axis.

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
	
	my $lineTheta0Deg  = eval($rps->{line}{angle0Deg});  # To set rod convexity direction.

	
	my ($rodDxs0,$rodDys0,$rodDzs0);
	
	# See if we have offset data:
	if (!($dXs->isempty or $dYs->isempty or $dXs->isempty)){
		# In this case, we have $dYs and $dZs as well, and nothing to do, since I presume the offsets were recorded from the same picture that gave the original handle direction.  This might wwnt to be rethought.
		
		die "Initialize rod from (DX,DY,DZ) not yet implented.\n";

		$rodDxs0 = $dXs;
		$rodDys0 = $dYs;
		$rodDzs0 = $dZs;
	
	} elsif (!$loadedThetas->isempty) {
		my $relThetas = ResampleThetas($loadedThetas,$rodSegLens);
		$relThetas = $relThetas(0:-2);	# Get rid of the extra zero.  But also should do better interpolation.
		
		# Set rod convexity from line initial direction:
		if ($lineTheta0Deg <= 0){$relThetas *= -1}
		
		if ($verbose>=3){pq $relThetas}
	
		# Driving plane rotation about x direction:
		my $lenYZ		= sqrt($driverDYs(0)**2 + $driverDZs(0)**2);
		my $axialAngle	= acos($driverDZs(0)/$lenYZ);
		
		# Initial handle angle in the vertical plane:
		my $theta0		= atan2($driverDXs(0),$driverDZs(0));
		
		pq($segLens);
		pq($axialAngle,$theta0);

		($rodDxs0,$rodDys0,$rodDzs0) =
			PlanarAnglesToOffsets($axialAngle,$theta0,$relThetas,$segLens);
		
	} else { die "ERROR: Could not find rod initial configuration data.\nStopped"}
	
	if ($verbose=>3){pq($rodDxs0,$rodDys0,$rodDzs0)}
	
	return ($rodDxs0,$rodDys0,$rodDzs0);
}



sub SetLineStartingConfig {
    my ($lineSegLens) = @_;
    
    ## Take the initial line configuration as straight and horizontal, deflected from straight downstream by the specified angle (pos is toward the plus Y-direction).
    
    PrintSeparator("Setting up starting line configuration");

    my $lineTheta0  = eval($rps->{line}{angle0Deg})*$pi/180;
    my $lineCurve0  = eval($rps->{line}{curve0InvFt})/12;    # 1/in
    
    #if ($lineTheta0 < 0){$lineCurve0 *= -1}
    
    #$lineTheta0 += $pi/2;
    my ($dzs0,$dxs0) = RelocateOnArc($lineSegLens,$lineCurve0,$lineTheta0);
    
    my $dys0 = zeros($dxs0);
    #if ($verbose>=3){pq($dxs0,$dys0,$dzs0)}
    
    if (DEBUG and $verbose>=4){pq($lineTheta0)}
    
    return ($dxs0,$dys0,$dzs0);
}




my ($dragSpecsNormal,$dragSpecsAxial,$segAirMultRand);
my ($rodLineStr,$driverAmbientStr);
my ($timeStr,$lineStr);
my ($T0,$Dynams0,$dT0,$dT);
my $numNodes;
my %opts_plot;
my ($T,$Dynams);
	# Will hold the complete integration record.  I put them up here since $T will be undef'd in SetupIntegration() as a way of indicating that the CastRun() initialization has not yet been done.

sub SetupIntegration { my $verbose = 1?$verbose:0;
    
    ## Initialize PDLs that used during the integration, importantly including those that will be held constant.
    
    # Note that most physical values are are calculated for the inertial nodes.  However, I find air drag is most easily computed at the rod and line segment midpoints, and the resulting forces redistributed to the nodes.  Thus,
    
    PrintSeparator("Setting up integration pdls");
    
    #print("\n\nWORRY about whether the frictional terms belong in KE or PE.\n\n");
    
    $numNodes = 1 + $numRodNodes + $numLineSegs;   # Starts with the handle bottom node, which $numRodNodes does not.
    if ($numNodes<3){die "There must be at least 3 nodes total.\n"}
    
    if (any($segWts) <= 0){die "Weight segment must be positive.\n"}
    
   
    
    PrintSeparator("Setting up air friction");
    
    # Air friction contributes damping to both the rod and the line.  I use the real air friction coeff, and appropriately modelled form factors.  In any case, the drag coeffs should be proportional to section surface area.  Eventually I might want to acknowledge that the flows around the rod's hex section and the lines round section are different.  See below and Calc_FluidDrags() for the details.
    
    # Setup drag for the line segments:
    $dragSpecsNormal    = Str2Vect($rps->{ambient}{dragSpecsNormal});
    $dragSpecsAxial     = Str2Vect($rps->{ambient}{dragSpecsAxial});
    
    
        # For slack line segments, I want to adjust the standard drag formula with a strain-weighted contribution computed as if the line were locally oriented in a completely random direction.  My formula for the drag multiplier in this case, assuming for simplicity only a v^2 dependence is F = (4/3pi)*rho*L*D*(C1A+C1N)*V^2:

    $segAirMultRand = 0;
    print "REMINDER:  Fix segAirMultRand.\n";
=for OLD WAY
    $segAirMultRand = (4/(3*$pi))*$massDensityAir*$segLens*$segDiams*
        ($airDragNormalCoeffs(1)+$airDragAxialCoeffs(1));
        
        pq($segAirMultRand);
=cut OLD WAY
        # And for the fly:
    
    PrintSeparator("Setting up the dynamical variables");
    
    # PDL variables updated during the integration.  The dynamical variables are stored as 1-D PDL vectors.  Keep in mind that PDL matrices are indexed by column, then row:
    
    #in setting up pTheta's want horizontal, right moving momentum.  What does this mean for pTheta?
    
    my $t0;
    my ($dxs0,$dys0,$dzs0,$qs0);
    
    if ($loadedState->isempty){
        
        $t0 = eval($rps->{integration}{t0});
        $T0 = $t0;
        
        my ($qs0,$qDots0);
        
        my ($rodDxs0,$rodDys0,$rodDzs0)     = map {zeros(0)} (0..2);
        my ($lineDxs0,$lineDys0,$lineDzs0)  = map {zeros(0)} (0..2);

        if ($numRodSegs){
			($rodDxs0,$rodDys0,$rodDzs0)  = SetRodStartingConfig($rodSegLens);
        }
        
        if ($numLineSegs) {
            # Take the initial line configuration as straight, deflected from the horizontal by the specified angle offset (up is negative):
            #pq($lineSegNomLens);
            ($lineDxs0,$lineDys0,$lineDzs0)  = SetLineStartingConfig($lineSegNomLens);
            pq($lineDxs0,$lineDys0,$lineDzs0);
        }
        
        #my $qDots0 = zeroes($qs0);
        # Implies all thetaDots and (dynamic) segDots zero, so all rod and line nodes still.
 
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
    
    $dT0	= eval($rps->{integration}{dt0});
    $dT		= eval($rps->{integration}{plotDt});
    if ($verbose>=3){pq($T0,$Dynams0)}
    
    SetEventTs($T0,$tipReleaseStartTime,$tipReleaseEndTime);
    
    my $runControlPtr          = \%rCastRunControl;
    my $loadedStateIsEmpty     = $loadedState->isempty;
    

    $lineStr    = GetLineStr()."\n".GetLeaderStr()."\n".GetTippetStr()."\n".GetFlyStr();
    $driverAmbientStr   = $driverStr."\n".GetAmbientStr();
    
    #pq($numLineSegs);die;
    %opts_plot = (gnuplot=>$gnuplot);
	
	$T = undef;
	
    Init_Hamilton("initialize",
                    $g,$rodLen,$actionLen,
                    $numRodSegs,$numLineSegs,
                    $segLens,$segCGs,$segCGDiams,
                    $segWts,zeros(0),$segKs,$segCs, # stretch Ks and Cs only
                    $rodTorqueKs,$rodTorqueCs,
                    $flyNomLen,$flyNomDiam,$flyWt,undef,
                    $dragSpecsNormal,$dragSpecsAxial,
                    $segAirMultRand,
                    $driverXSpline,$driverYSpline,$driverZSpline,
                    $driverDXSpline,$driverDYSpline,$driverDZSpline,
                    $frameRate,$driverStartTime,$driverEndTime,
                    $tipReleaseStartTime,$tipReleaseEndTime,
                    $T0,$Dynams0,$dT0,$dT,
                    $runControlPtr,$loadedStateIsEmpty);
}


my (%opts_GSL,$t0_GSL,$t1_GSL,$dt_GSL);
my $elapsedTime_GSL;
my ($finalT,$finalState);
my ($plotTs,$plotXs,$plotYs,$plotZs,$plotNumRodNodes,$plotErrMsg);
my ($plotXLineTips,$plotYLineTips,$plotZLineTips,
    $plotXLeaderTips,$plotYLeaderTips,$plotZLeaderTips);
my ($holding,$XTip0,$YTip0,$ZTip0);;
my ($iEvent,$init_numLineSegs);
# These include the handle butt.



sub RCastRun {
    
    ## Do the integration.  Either begin run or continue... Looks for a set return flag,  takes up where it left off (unless reset), and plots on return.  NOTE that the PAUSE button will only be reacted to during a call to DE, so in particular, while the solver is running.
    
    PrintSeparator("Doing the integration");
    
    my $JACfac;
	#my $nextNumLineSegs;
	
    if (ref($T) ne 'PDL'){
	
	    PrintSeparator("In caller initialization block",3);

        
        #$init_numRodSegs    = $numRodSegs;
        $init_numLineSegs   = $numLineSegs;
        
        $elapsedTime_GSL    = 0;
        
        $t0_GSL             = Get_T0();
        
        $t1_GSL             = eval($rps->{integration}{t1});   # Requested end
        $dt_GSL             = $dT;
        my $lastStep_GSL       = int(($t1_GSL-$t0_GSL)/$dt_GSL);
        $t1_GSL             = $t0_GSL+$lastStep_GSL*$dt_GSL;    # End adjusted to keep the reported step intervals constant.
        
        $Dynams             = Get_DynamsCopy(); # This includes good initial $ps.
        if($verbose>=3){pq($t0_GSL,$t1_GSL,$dt_GSL,$Dynams)}
        
        
        $lineSegNomLens     = $segLens(-$init_numLineSegs:-1);
 
        $holding            = ($eventTs->isempty) ? 0 : 1;
        $iEvents			= 0;
        if (DEBUG and $verbose>=4){pq($eventTs)}
        
        if ($holding == 1){
			
			#$nextNumLineSegs    = $init_numLineSegs-1;
			#$nextDynams_GSL		= StripDynams($Dynams);
			
            #Init_Hamilton("restart_cast",$t0_GSL,$nextNumLineSegs,$nextDynams_GSL,$holding);
            Init_Hamilton("restart_cast",$t0_GSL,StripDynams($Dynams),$holding);
            ($XTip0,$YTip0,$ZTip0) = Get_HeldTip();
			pq($XTip0,$YTip0,$ZTip0);
        } # else noop.  Holding was turned off during Init_Hamilton("initialize",...).
        
        my $h_init  = eval($rps->{integration}{dt0});
        %opts_GSL	= (type=>$rps->{integration}{stepperName},h_init=>$h_init);
        if ($verbose>=3){pq(\%opts_GSL)}
        
        $T = pdl($t0_GSL);   # To indicate that initialization has been done.  Prevents repeated initializations even if the user interrups during the first plot interval.
        
        if ($verbose>=2){print "Solver startup can be especially slow.  BE PATIENT.\n"}
        else {print "RUNNING SILENTLY, wait for return, or hit PAUSE to see the results thus far.\n"}
    }
    
    my $nextStart_GSL   = $T(-1)->sclr;
 	my $nextDynams_GSL;
	if ($holding != 1){	$nextDynams_GSL = $Dynams(:,-1)					}
	else {				$nextDynams_GSL = StripDynams($Dynams(:,-1))	}
	
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
        if ($verbose>=2){printf("\nt=%.3f   ",$thisStart_GSL)}
        
		my @tempArray = $nextDynams_GSL->list;
		my $theseDynams_GSL_aRef = \@tempArray;	# Can't figure out how to do this in 1 go.
		#my $reftype = ref($theseDynams_GSL_aRef);
		#pq($reftype); die;

        my $thisStop_GSL;
        my $numSteps_GSL;
        my $nextEvent_GSL;
        my $stopIsUniform;
        my $solution;
        
        if (!$holding){   # Uniform starts and stops only.  On user interrup, starts at last reported time.
            $thisStop_GSL   = $t1_GSL;
            $numSteps_GSL   = int(($thisStop_GSL-$t0_GSL)/$dt_GSL);
            $stopIsUniform  = 1;
        }
        else {    # There are restarts.
			
            $nextEvent_GSL    = $eventTs($iEvents)->sclr;
            if ( $thisStart_GSL > $nextEvent_GSL) {
                die "ERROR:  Detected jumped event.\n";
            } elsif( $thisStart_GSL == $nextEvent_GSL) {
                $nextEvent_GSL    = $eventTs(++$iEvents)->sclr;
            }
			
            my $thisStep        = int(($thisStart_GSL-$t0_GSL)/$dt_GSL);
            my $lastUniformStop = $t0_GSL + $thisStep*$dt_GSL;
            my $startIsUniform  = ($thisStart_GSL == $lastUniformStop) ? 1 : 0;
			
            if ($startIsUniform) {
                
                my $boundedNextEvent = ($nextEvent_GSL > $t1_GSL) ? $t1_GSL : $nextEvent_GSL;
                
                $numSteps_GSL       = int(($boundedNextEvent-$thisStart_GSL)/$dt_GSL);
                if ($numSteps_GSL){     # Make whole steps to just before the next restart.
                    $thisStop_GSL   = $thisStart_GSL + $numSteps_GSL*$dt_GSL;
                    $stopIsUniform  = 1;
                } else {    # Need to make a single partial step to take us to the next restart or the end.
                    $thisStop_GSL   = $boundedNextEvent;
                    $numSteps_GSL   = 1;
                    $stopIsUniform  = ($thisStop_GSL == $lastUniformStop+$dt_GSL) ? 1 : 0;
                }
            }
            else { # start is not uniform, so make no more than one step.
                
                $numSteps_GSL       = 1;
                
                my $nextUniformStop = $lastUniformStop + $dt_GSL;
                if ($nextEvent_GSL < $nextUniformStop) {
                    $thisStop_GSL   = $nextEvent_GSL;
                    $stopIsUniform  = 0;
                } else {
                    $thisStop_GSL   = $nextUniformStop;
                    $stopIsUniform  = 1;
                }
            }
            
            if($verbose>=3){pq($thisStart_GSL,$thisStop_GSL,$lastUniformStop,$startIsUniform,$stopIsUniform)}
        }
        
        
        
        if ($verbose>=3){print "\n SOLVER CALL: start=$thisStart_GSL, end=$thisStop_GSL, nSteps=$numSteps_GSL\n\n"}
        if($thisStart_GSL >= $thisStop_GSL){die "ERROR: Detected bad integration bounds.\n"}
        
        $solution = pdl(ode_solver([\&DEfunc_GSL,\&DEjac_GSL],[$thisStart_GSL,$thisStop_GSL,$numSteps_GSL],$theseDynams_GSL_aRef,\%opts_GSL));
        
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
        $nextStart_GSL  = $solution(0,-1)->sclr;    # Latest report time.
        $nextDynams_GSL = $solution(1:-1,-1)->flat;

        if ($verbose>=3){print "END_TIME=$nextStart_GSL\nEND_DYNAMS=$nextDynams_GSL\n\n"}
        #pq($T,$Dynams);

		
        # There  is always at least one time (starting) in solution.  Never keep the starting data:
        my ($nCols,$nTimes) = $solution->dims;
        
        if ($nextStart_GSL == $thisStop_GSL) { # Got to the planned end of block run (so there are at least 2 rows.
            if (!$stopIsUniform) {  # The planned stop is not uniform.  Don't keep the stop data.  Note, however, that we will start the next solver run from here.
                $solution   = $solution(:,0:-2);
                $nTimes--;
            }
        }
        
        # In any case, we never keep the run start data:
        $solution   = ($nTimes == 1) ? zeros($nCols,0) : $solution(:,1:-1);
        #pq($solution);
        
        $wasHolding = $holding;
        my ($ts,$paddedDynams) = PadSolution($solution,$wasHolding);
        $T = $T->glue(0,$ts);
        $Dynams = $Dynams->glue(1,$paddedDynams);
        if (DEBUG and $verbose>=4){pq($T,$Dynams)}
        
        
        my $nextDynams;
        pq($holding);
        if ($holding == 1 and $nextStart_GSL == $nextEvent_GSL){
            $holding = -1;
            #$nextNumLineSegs    = $init_numLineSegs;
            $nextDynams_GSL		= RestoreDynams($nextStart_GSL,$nextDynams_GSL);
        } elsif ($holding == 1){ # Interrupt during hold.
            #$nextNumLineSegs    = $init_numLineSegs - 1;
            #$nextDynams         = $theseDynams;
        } elsif ($holding == -1 and $nextStart_GSL == $nextEvent_GSL){
            $holding = 0;
            #$nextNumLineSegs    = $init_numLineSegs;
            #$nextDynams         = $theseDynams;
        } else {
            #$nextNumLineSegs    = $init_numLineSegs;
            #$nextDynams         = $theseDynams;
        }
        
        if ($nextStart_GSL < $t1_GSL and $tStatus >= 0) {
            # On any restart, if either no error, or user interrupt.
			#Init_Hamilton("restart_cast",$nextStart_GSL,$nextNumLineSegs,$nextDynams,$holding);
			Init_Hamilton("restart_cast",$nextStart_GSL,$nextDynams_GSL,$holding);
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
    
    
    PrintSeparator("\nOn solver return");
    if ($verbose){
        
        my ($DE_numCalls,$DEfunc_numCalls,$DEjac_numCalls) = DE_GetCounts();
        pq($DE_numCalls,$DEfunc_numCalls,$DEjac_numCalls,$elapsedTime_GSL);
    }
    
    
    # Plot to x11 terminal and write plotting file:
    
    my $duration = sprintf("%04d",1000*sclr($plotTs(-1)));
    $rps->{file}{save} = '_'.$runIdentifier.'_'.$duration;
    
    $plotErrMsg = $tErrMsg;
    
    #pq $plotErrMsg;
    
    my $titleStr = "RCast - " . $dateTimeLong;
    
	
	my $plotBottom = 0;
	my $plotNumRodSegs = $plotNumRodNodes - 1;

    RCommonPlot3D('window',$rps->{file}{save},$titleStr,$paramsStr,
    $plotTs,$plotXs,$plotYs,$plotZs,$plotXLineTips,$plotYLineTips,$plotZLineTips,$plotXLeaderTips,$plotYLeaderTips,$plotZLeaderTips,$plotNumRodSegs,$plotBottom,$plotErrMsg,$verbose,\%opts_plot);
    
	
    
    # If integration has completed, tell the caller:
    if ($tPlot>=$t1_GSL or $tStatus < 0) {
        if ($tStatus < 0){print "\n";pq($tStatus,$tErrMsg)}
        &{$rCastRunControl{callerStop}}();
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
	
	pq($Xs,$Ys,$Zs);
	
    my $dxLast = $XTip0-$Xs(-1,:);
    my $dyLast = $YTip0-$Ys(-1,:);
    my $dzLast = $ZTip0-$Zs(-1,:);
	
	my $zerosPad = zeros(1,$numTs);
	
	pq($XTip0,$YTip0,$ZTip0);
	pq($dxLast,$dyLast,$dzLast);
    
    my $restoredDynams =
        $dxs->glue(0,$dxLast)->glue(0,$dys)->glue(0,$dyLast)->glue(0,$dzs)->glue(0,$dzLast)
        ->glue(0,$dxps)->glue(0,$zerosPad)->glue(0,$dyps)->glue(0,$zerosPad)->glue(0,$dzps)->glue(0,$zerosPad);
    
    ### ??? Actually, is setting the last segment momenta correct.  Any mass associated with it would be moving due to stretching.  Should really put in the appropriate qDots and then set ps from them.
    
    pq($restoredDynams);
	
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
    
    my ($dthetas,$dxs,$dys,$dthetaps,$dxps,$dyps) = UnpackDynams($dynams);
    #pq($dthetas,$dxs,$dys,$dthetaps,$dxps,$dyps,$numLineNodes);
    
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
	
    ## Return the cartesian coordinates Xs, Ys and Zs of all the rod and line NODES.  These are used for plotting and saving.
    my ($driverX,$driverY,$driverZ,$driverDX,$driverDY,$driverDZ) = Calc_Driver($t);
    
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
        my $driverLength = $rodLen-$actionLen;
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
    
    my $str = "RodID=$rodIdentifier\n";
    $str .= " Lens(total,action)=($rodLenFt,$actionLenFt)\n";
    $str .= " NumSects,Mults(Ferrule,V&G)=($numSections,$rps->{rod}{ferruleKsMult},$rps->{rod}{vAndGMultiplier})\n";
    $str .= " Dens,FibGrad,WallThick=($rps->{rod}{densityLbFt3},$rps->{rod}{fiberGradient},$rps->{rod}{maxWallThicknessIn})\n";
    $str .= " Mods(elastic,damping)=($rps->{rod}{elasticModulusPSI},$rps->{rod}{dampingModulusStretchPSI})";
    
    return $str;
}

sub GetLineStr {
    
    my $str = "ActiveLength=$activeLenFt\n";
    $str .= "LineID=$rps->{line}{identifier}\n";
    $str .= " NomWt,NomDiam,CoreDiam=($rps->{line}{nomWtGrsPerFt},$rps->{line}{nomDiameterIn},$rps->{line}{coreDiameterIn})\n";
    $str .= " Len==$rps->{line}{activeLenFt}\n";
    $str .= " Mods(elastic,damping)=($rps->{line}{coreElasticModulusPSI},$rps->{line}{dampingModulusPSI})";
    
    return $str;
}


sub GetLeaderStr {
    
    my $str = "Leader=$leaderStr\n";
    $str .= " NomWt,Diam=($rps->{leader}{wtGrsPerFt},$rps->{leader}{diamIn})\n";
    $str .= " Len=$leaderLenFt\n";
    $str .= " Mods(elastic,damping)=($leaderElasticModPSI,$leaderDampingModPSI)";
    
    return $str;
}


sub GetTippetStr {
    
    my $str = "$rps->{tippet}{text}\n";
    $str .= " Diam=$rps->{tippet}{diamIn}\n";
    $str .= " Len=$tippetLenFt\n";
    $str .= " Mods(elastic,damping)=($tippetElasticModPSI,$tippetDampingModPSI)";
    
    return $str;
}


sub GetFlyStr {
    
    my $str = "FlyWt=$rps->{fly}{wtGr}\n";
    $str .= " NomDiam,NomLen=($rps->{fly}{nomDiamIn},$rps->{fly}{nomLenIn})";
    
    return $str;
}



sub GetAmbientStr {
    
    my $str = "Gravity=$rps->{ambient}{gravity}\n";
    $str .= "DragSpecsNormal=$rps->{ambient}{dragSpecsNormal}\n";
    $str .= "DragSpecsAxial=$rps->{ambient}{dragSpecsAxial}\n";
    
    return $str;
}



sub DiamsToGrsPerFoot{
    my ($diams,$spGr) = @_;
    
## For leaders. Spec. gr nylon 6/6 is 1.14;

#  Density of nylon 6/6 is 0.042 lbs/in3.
# so 0.0026 oz/in3;
    
    my $volsPerFt = ($pi/4)*12*$diams**2;
    my $ozPerFt     = $volsPerFt*$waterOzPerIn3*$spGr;
    my $grsPerFt    = $ozPerFt*$grPerOz;
    return $grsPerFt;
}


# SPECIFIC PLOTTING FUNCTIONS ======================================


sub PlotHandleSpline {
    my ($numTs,$driverXSpline,$driverYSpline,$driverZSpline,
        $driverDXSpline,$driverDYSpline,$driverDZSpline) = @_;
    
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
    #pq($dataXs,$dataYs,$dataZs);
    
    Plot($dataTs,$dataXs,"X Splined",$dataTs,$dataYs,"Y Splined",$dataTs,$dataZs,"Z Splined",$dataTs,$dataDXs,"DX Splined",$dataTs,$dataDYs,"DY Splined",$dataTs,$dataDZs,"DZ Splined","Splines as Functions of Time");
}




sub RCastSave { my $verbose = 1?$verbose:0;
    my ($filename) = @_;

    my($basename, $dirs, $suffix) = fileparse($filename);
#pq($basename,$dirs$suffix);

    $filename = $dirs.$basename;
    if ($verbose>=2){print "Saving to file $filename\n"}

    my $titleStr = "RCast - " . $dateTimeLong;

    if ($rps->{integration}{savePlot}){
        RCommonPlot3D('window',$rps->{file}{save},$titleStr,$paramsStr,
        $plotTs,$plotXs,$plotYs,$plotZs,$plotXLineTips,$plotYLineTips,$plotZLineTips,$plotXLeaderTips,$plotYLeaderTips,$plotZLeaderTips,$plotNumRodNodes,$plotErrMsg,$verbose,\%opts_plot);
    }

#pq($plotTs,$plotXs,$plotYs);
                   
    if ($rps->{integration}{saveData}){
        RCommonSave3D($dirs.$basename,$rCastOutFileTag,$titleStr,$paramsStr,
        $plotTs,$plotXs,$plotYs,$plotZs,$plotXLineTips,$plotYLineTips,$plotZLineTips,$plotXLeaderTips,$plotYLeaderTips,$plotZLeaderTips,$plotNumRodNodes,$plotErrMsg,
        $finalT,$finalState,$segLens);
    }
}


sub RCastPlotExtras {
    my ($filename) = @_;
    
    if ($rps->{driver}{plotSplines}){PlotHandleSpline('file',121,$filename.'_driver')}

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

RHexCast3D - A PERL program that simulates the motion of a multi-component fly line (line proper,
leader, tippet and fly) in a flowing stream under the influence of gravity, buoyancy, fluid friction,
internal stresses, and a user defined initial configuration, rod tip motion, and line stripping.
RHexCast3D is one of the two main programs of the RHex Project.


=head1 SYNOPSIS

Enter perl RHexCast3D.pl in a terminal window, or double-click on the shell script RHexCast3D.sh
in the finder window, or run the stand-alone executable RHexCast3D if it is available.
  
=head1 DESCRIPTION

The results of the calculation are displayed as constant-time-interval colored traces on a 3D plot
that can be rotated at will by the motion of the cursor.  The earliest traces are shown in green and
the latest in red, with the intermediate traces shown as brownish shades that are the combination of
green and red in appropriate proportion.  Open circles, solid circles, diamonds and squares mark the
locations of the rod tip, line-leader and leader-tippet junctions, and the fly.
    
The interactive control panel allows the setting of parameters that control the details of the line
make-up, the water flow, the initial line location, the rod tip movement, the stripping starting
time and velocity, and details of the integration and plotting.  In addition, the panel allows for
the selection of a parameter preference file, which presets all the parameters to a
previously saved condition, as well as the selection of files that define specific fly-lines and
leaders, and of another that loads a textual description of a rod-tip motion.  Use of the line, leader
and motion files allows the simulation of any fly line with any motion, not just those constructable
using the parameters.

More information, including a detailed description of the parameters and their allow values, is
available from the help menu located in the upper left corner of the control panel.

The code in this file builds and deploys the control panel, whose buttons invoke functions in RSwing3D.pm
that set up and run a Gnu Scientific Library ODE solver.  The solver is called from RUtils::DiffEq via an
XS interface. The solver integrates Hamilton's equations, calling a function in RHexHamilton3D.pm that provides
time derivatives of the dynamical variables at configurations set by the solver.  The GSL solver can invoke
any of a number of different stepping algorithms.  Some of these require knowledge of a Jacobian matrix.
This is provided numerically by the numjac function in RUtils::NumJac.

RUtils::Print and RUtils::Plot provide quick and simple printing and plotting capabilities, while RCommon.pm
provides very specialized utility functions that are used by both the Swing and Cast programs.  RCommonPlot3D.pm
does the plotting for all the programs of the RHex project.  All of the modules mentioned have their own POD
documentation.

=head1 A USEFUL NOTE

Every time a simulation run goes to completion, or is paused or stopped by user action, plot is drawn
that depicts the results up to that point.  Subsequent continuation or starting of a new run, when they
stop, produces another plot.  And so on.  These plots persist, so quite a few of them can accumulate.
You can manually go and close each with its window's close button, but that can become tedious.  A much
quicker procedure is to first save your parameters, and then simply close the Terminal window that appeared
when this program was launched.  That will cause all the plots to disappear.  Then simply relaunch this
program.  Because you have saved the parameters, the new launch will start where the old one left off.

=head1 AUTHOR

Rich Miller, E<lt>rich@ski.orgE<gt>

=head1 COPYRIGHT AND LICENSE

RHex - 3D dyanmic simulation of fly casting and swinging.

Copyright (C) 2019 Rich Miller

This file is part of RHex.

RHex is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

RHex is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with RHex.  If not, see <https://www.gnu.org/licenses/>.

=cut

