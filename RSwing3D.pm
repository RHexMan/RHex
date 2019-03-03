#!/usr/bin/perl

#############################################################################
## Name:			RSwing3D.pm
## Purpose:			Integrates Hamiltons equations in 3D to simulate fly line
##                      and streamer swinging and sinking.
## Author:			Rich Miller
## Modified by:	
## Created:			2019/2/18
## Modified:
## RCS-ID:
## Copyright:		(c) 2019 Rich Miller
## License:			This program is free software; you can redistribute it and/or
##					modify it under the same terms as Perl itself
#############################################################################

# syntax:  use RSwing3D;


# DESCRIPTION:  RSwing is a graphical interface to a program that simulates the motion of a bamboo hex rod, line, leader, and fly during a cast.  The user sets parameters which specify the physical and dimensional properties of the above components as well as the time-motion of the rod handle, which is the ultimate driver of the cast.  The program outputs datafiles and cartoon images that show successive stop-action frames of the components.  Parameter settings may be saved and retrieved for easy project management.


#Documentation for the individual setup and run parameters may found in the Run Params section below, where the fields of rSwingRunParams are defined and defaulted.


# Measured level leaders ===================================

#   Type            Diam(in)        TotalWt(gm) Length(ft)  calc Wt/Ft(gr) Nom sink(ips)
#   Airflow T7      0.027           5.0         10          7.7             6.5
#   Zink 9          0.037           6.5         12          8.4
#   Zink 15         0.048           12.5        13          14.8            6.2
#   Zink 19         0.054           16.1        12'2"       20.4            6.7

# Measured tapered leaders ===================================

#   Type            Diams(thou)@    tip 0   2   4   6   8   10  TotalWt(gm) Length(ft)
#   Versi 7.0ips                    20  27  28  30  32  34  34  5.2         10 nom,11 meas, 8" clear tip
#   Versi 3.9ips                    20  27  30  34  39  43  43  4.5         10'10" meas, 8" clear tip
#   Versi 7.0ips                    20  30  40  48  47  48  49  4.5         10'6" meas, 7" clear tip

# Weighed flies ===================================

# R's Intruder (Max)            74 gr
# MrPimp (#4)                   24 gr
# MrPimp (#6)                   19 gr
# EggSuckingLeech (#6)          6 gr
# Halo (#3)                     8 gr
# TungConeZonkerLeech (max)     30 gr


# Compile directives ==================================
package RSwing3D;

use warnings;
use strict;

use Exporter 'import';
our @EXPORT = qw(DEBUG $verbose $vs $tieMax %rSwingRunParams %rSwingRunControl $rSwingOutFileTag RSwingSetup LoadLine LoadLeader LoadDriver RSwingRun RSwingSave RSwingPlotExtras);

use Time::HiRes qw (time alarm sleep);
use Switch;
use File::Basename;
use Math::Spline;
use Math::Round;

use PDL;
    # Import main PDL module (see PDL.pm for equivalents).  In particular, imports PDL::Math, which redefines many POSIX math functions.  To get the original, call POSIX::aFunction.
use PDL::NiceSlice;
use PDL::AutoLoader;    # MATLAB-like autoloader.

use PerlGSL::DiffEq ':all';

use RPrint;
use RPlot;
use RCommon;
use RHamilton3D;
use RCommonPlot3D;


# Run params ==================================

$verbose = 1;   # See RHexCommon.
    
our $tieMax = 2;
    # Values of verbose greater than this cause stdout and stderr to go to the terminal window, smaller values print to the widget's status window.  Set to -1 for serious debugging.


# Declare variables and set defaults  -----------------
our $rSwingOutFileTag = "#RSwingOutputFile";

our %rSwingRunParams;
#our %rSwingRunParams = (file=>{},line=>{},ambient=>{},configuration=>{},driver=>{},integration=>{},misc=>{});
    ### Defined just below.

### !!!! NOTE that after changing this structure, you should delete the widget prefs file.

my $rps = \%rSwingRunParams;

# SPECIFIC DISCUSSION OF PARAMETERS, TYPICAL AND DEFAULT VALUES:

$rps->{file} = {
    rSwing    => "RSwing3D 1.1, 2/17/2019",   # Used for verification that input file is a sink settings file.
    settings        => "RHexSwing3D.prefs",
    line            => "",
    leader          => "",
    driver          => "",
    save            => "",
        # If non-empty, there is something to plot.
};


$rps->{line} = {
    identifier              => "",
    activeLenFt             => 30,
        # Total desired length from rod tip to fly.
    nomWtGrsPerFt           => 6,
    # This is the nominal.  If you are reading from a file, must be an integer.
    estimatedDensity        => 0.8,
    # Only used if line read from a file and finds no diameters.
    nomDiameterIn           => 0.060,
    coreDiameterIn          => 0.020,
    # Make a guess.  Used in computing effective Hook's Law constant from nominal elastic modulus.
    coreElasticModulusPSI   => 1.52e5,        # 2.5e5 seems not bad, but the line hangs in a curve to start so ??
    # I measured the painted 4 wt line (tip 12'), and got corresponding to assumed line core diam of 0.02", EM = 1.52e5.
    # Try to measure this.  Ultimately, it is probably just the modulus of the core, with the coating not contributing that much.  0.2 for 4 wt line, 8' long is ok.  For 20' 7wt, more like 2.  This probably should scale with nominal line weight.   A tabulated value I found for Polyamides Nylon 66 is 1600 to 3800 MPa (230,000 to 550,000 psi.)
    dampingModulusPSI          => 1,
    # Cf rod damping modulus.  I don't really understand this, but numbers much different from 1 slow the integrator way down.  For the moment, since I don't know how to get the this number for the various leader and tippet materials, I am taking this value for those as well.
};



$rps->{leader} = {
    identifier      => "",
    idx             => 1,   # Index in the leader menu.
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
    nomDispVolIn3   => 0.25,
};



$rps->{ambient} = {
    gravity                 => 1,
        # Set to 1 to include effect of vertical gravity, 0 is no gravity, any value ok.
    dragSpecsNormal          => "11,-0.74,1.2",
    dragSpecsAxial           => "11,-0.74,0.01",
    # RE in [25,5K], Wolfram given very nearly constant 1.0., this per unit length.
    #    CDragAirAxial         => 0.010,   # 0.008(smooth)-0.011(rough) from OrcaFlex, but water, air?
};

$rps->{stream} = {
    bottomDepthFt           => 10,
    surfaceVelFtPerSec      => 4,
    surfaceLayerThicknessIn => 1,
    halfVelThicknessFt      => 1,
    profile                 => 0,
    profileText             => "profile - const",

    horizHalfWidthFt        => 10,
    horizExponent           => 2,
    
    
    showProfile             => 0,
};


$rps->{configuration} = {
    crossStreamAngle        => 0,   # Radians, measured from downstream.
    curvatureInvFt          => 1/100, # Plus is convex downstream, zero (or +/- inf) is straight.
    preStretchMult          => 1.001,    # For reasons I don't understand, a little pre-stretching of the line lets the solver (even a stiff one) get started much faster.
    tuckHeightFt            => 0,
    tuckVelFtPerSec         => 0,
};

$rps->{driver} = {
    laydownIntervalSec      => 0,

    sinkIntervalSec         => 2.5,
    stripRateFtPerSec       => 0,

    startCoordsFt           => "0,5,0",
    endCoordsFt             => "0,1,0",
    pivotCoordsFt           => "0,0,5",
    trackCurvatureInvFt     => 1/13,
    trackSkewness           => 0,   # Positive is more curved later.
    startTime               => 3,
    endTime                 => 7,
    velocitySkewness        => 0,   # Positive is faster later later.
    showTrackPlot           => 0,
};


$rps->{integration} = {
    numSegs        => 10,
    segExponent     => 1.33,
    # Bigger than 1 concentrates more line nodes near rod tip.
    t0              => 0.0,     # initial time
    t1              => 1.0,     # final time.  Typically, set this to be longer than the driven time.
    dt0             => 0.0001,    # initial time step - better too small, too large crashes.
    minDt           => 1.e-7,   # abandon integration and return if seemingly stuck.    
    plotDt          => 1/60,    # Set to 0 to plot all returned times.
    plotZScale      => 1.0,
    
    stepperItem     => 0,
    stepperName     => "msbdf_j",
    
    showLineVXs     => 0,
    plotLineVYs     => 0,
    plotLineVAs     => 0,
    plotLineVNs     => 0,
    plotLine_rDots  => 0,

    savePlot    => 1,
    saveData    => 1,

    verbose         => 2,
};



our %rSwingRunControl = (
    callerUpdate        => sub {},
        # Called from the integration loop to allow the widget to operate.
    callerStop          => sub {},
        # Called on completion of the full integration.
    callerRunState      => 0
);


# Package internal global variables ---------------------
my ($dateTimeLong,$dateTimeShort,$runIdentifier);

#print Data::Dump::dump(\%rSwingRunParams); print "\n";



# Package subroutines ------------------------------------------
sub RSwingSetup {
    
    ## Except for the preference file, files are not loaded when selected, but rather, loaded when run is called.  This lets the load functions use parameter settings to modify the load -- what you see (in the widget) is what you get. This procedure allows the preference file to dominate.  Suggestions in the rod files should indicate details of that particular rod construction, which the user can bring over into the widget via the preferences file or direct setting, as desired.
    
    SmoothChar_Setup(100);
    
    $dateTimeLong = scalar(localtime);
    if ($verbose>=2){print "$dateTimeLong\n"}
    
    my($date,$time) = ShortDateTime;
    $dateTimeShort = sprintf("(%06d_%06d)",$date,$time);
    
    $runIdentifier = 'RUN'.$dateTimeShort;
    
    if (DEBUG and $verbose>=4){print Data::Dump::dump(\%rSwingRunParams); print "\n"}
    
    my $ok = CheckParams();
    if (!$ok){print "ERROR: Bad params.  Cannot proceed.\n\n";return 0};
    
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

my $loadedDiams;
my $loadedParamsStr;
my $deflectionStr;
my $lineIdentifier;


sub CheckParams{
    
    ## I have chosen to do the checking here, rather than use the widget validate mechanism, mostly just because it seems easier to code.

    PrintSeparator("Checking Params");

    my $ok = 1;
    my ($str,$val);
    
    $str = "activeLenFt"; $val = $rps->{line}{$str};
    if ($val <= 0){$ok=0; print "ERROR: $str = $val - active length must be positive.\n"}
    elsif($verbose>=1 and ($val < 10 or $val > 40)){print "WARNING: $str = $val - Typical range is [10,40].\n"}
    
    $str = "nomWtGrsPerFt"; $val = $rps->{line}{$str};
    if ($val < 0){$ok=0; print "ERROR: $str = $val - line nominal weight must be non-negative.\n"}
    elsif($verbose>=1 and ($val > 15)){print "WARNING: $str = $val - Typical range is [1,15].\n"}
    
    $str = "estimatedDensity"; $val = $rps->{line}{$str};
    if ($val <= 0){$ok=0; print "ERROR: $str = $val - Must be positive.\n"}
    elsif($verbose>=1 and ($val < 0.5 or $val > 1.5)){print "WARNING: $str = $val - Typical range is [0.5,1.5].\n"}
    
    $str = "nomDiameterIn"; $val = $rps->{line}{$str};
    if ($val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 0.03 or $val > 0.09)){print "WARNING: $str = $val - Typical range is [0.030,0.090].\n"}

    
    $str = "coreDiameterIn"; $val = $rps->{line}{$str};
    if ($val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 0.01 or $val > 0.05)){print "WARNING: $str = $val - Typical range is [0.01,0.05].\n"}
    
    $str = "coreElasticModulusPSI"; $val = $rps->{line}{$str};
    if ($val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 1e5 or $val > 4e5)){print "WARNING: $str = $val - Typical range is [1e5,4e5].\n"}
    
    $str = "dampingModulusPSI"; $val = $rps->{line}{$str};
    if ($val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 0.5 or $val > 1.5)){print "WARNING: $str = $val - Values much different from 1 slow the solver down a great deal, while those much above 10 lead to anomalies during stripping.\n"}
    
    $str = "lenFt"; $val = $rps->{leader}{$str};
    if ($val < 0){$ok=0; print "ERROR: $str = $val - leader length must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 5 or $val > 15)){print "WARNING: $str = $val - Typical range is [5,15].\n"}
    
    $str = "wtGrsPerFt"; $val = $rps->{leader}{$str};
    if ($val < 0){$ok=0; print "ERROR: $str = $val - weights must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 5 or $val > 15)){print "WARNING: $str = $val - Typical range is [7,18].\n"}
    
    $str = "diamIn"; $val = $rps->{leader}{$str};
    if ($val <= 0){$ok=0; print "ERROR: $str = $val - diams must be positive.\n"}
    elsif($verbose>=1 and ($val < 0.004 or $val > 0.050)){print "WARNING: $str = $val - Typical range is [0.004,0.050].\n"}
    
    $str = "lenFt"; $val = $rps->{tippet}{$str};
    if ($val < 0){$ok=0; print "ERROR: $str = $val - lengths must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 2 or $val > 12)){print "WARNING: $str = $val - Typical range is [2,12].\n"}
    
    $str = "diamIn"; $val = $rps->{tippet}{$str};
    if ($val < 0){$ok=0; print "ERROR: $str = $val - diams must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 0.004 or $val > 0.012)){print "WARNING: $str = $val - Typical range is [0.004,0.012].\n"}
    
    
    $str = "wtGr"; $val = $rps->{fly}{$str};
    if ($val < 0){$ok=0; print "ERROR: $str = $val - Fly weight must be non-negative.\n"}
    elsif($verbose>=1 and ($val > 15)){print "WARNING: $str = $val - Typical range is [0,15].\n"}
    
    $str = "nomDiamIn"; $val = $rps->{fly}{$str};
    if ($val < 0){$ok=0; print "ERROR: $str = $val - Fly nom diam must be non-negative.\n"}
    elsif($verbose>=1 and ($val > 0.25)){print "WARNING: $str = $val - Typical range is [0.1,0.25].\n"}
    
    $str = "nomLenIn"; $val = $rps->{fly}{$str};
    if ($val < 0){$ok=0; print "ERROR: $str = $val - Fly nom diam must be non-negative.\n"}
    elsif($verbose>=1 and ($val > 1)){print "WARNING: $str = $val - Typical range is [0.25,1].\n"}
    
    $str = "nomDispVolIn3"; $val = $rps->{fly}{$str};
    if ($val < 0){$ok=0; print "ERROR: $str = $val - Fly nom volume must be non-negative.\n"}
    elsif($verbose>=1 and ($val > 0.005)){print "WARNING: $str = $val - Typical range is [0,0.005].\n"}
    
    $str = "gravity"; $val = $rps->{ambient}{$str};
    if ($val < 0){$ok=0; print "ERROR: $str = $val - Gravity must be must be non-negative.\n"}
    elsif($verbose>=1 and ($val != 1)){print "WARNING: $str = $val - Typical value is 1.\n"}
    
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
    
    $str = "sinkIntervalSec"; $val = $rps->{driver}{$str};
    if ($val < 0){$ok=0; print "ERROR: $str = $val - Sink interval must be must be non-negative.\n"}
    elsif($verbose>=1 and $val > 15){print "WARNING: $str = $val - Typical range is [0,15].\n"}
    
    $str = "stripRateFtPerSec"; $val = $rps->{driver}{$str};
    if ($val < 0){$ok=0; print "ERROR: $str = $val - Strip rate must be must be non-negative.\n"}
    elsif($verbose>=1 and $val > 5){print "WARNING: $str = $val - Typical range is [0,5].\n"}
    
    $str = "bottomDepthFt"; $val = $rps->{stream}{$str};
    if ($val <= 0){$ok=0; print "ERROR: $str = $val - Bottom depth must be must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 3 or $val > 15)){print "WARNING: $str = $val - Typical range is [3,15].\n"}
    
    $str = "surfaceLayerThicknessIn"; $val = $rps->{stream}{$str};
    if ($val < 0){$ok=0; print "ERROR: $str = $val - Water surface layer thickness must be must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 0.1 or $val > 2)){print "WARNING: $str = $val - Typical range is [0.1,2].\n"}
    
    $str = "surfaceVelFtPerSec"; $val = $rps->{stream}{$str};
    if ($val < 0){$ok=0; print "ERROR: $str = $val - Water surface velocity must be must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 1 or $val > 7)){print "WARNING: $str = $val - Typical range is [1,7].\n"}
    
    $str = "halfVelThicknessFt"; $val = $rps->{stream}{$str};
    if ($val <= 0 or $val > $rps->{stream}{bottomDepthFt}/2){$ok=0; print "ERROR: $str = $val - Half thickness must be positive, and no greater than half the water depth.\n"}
    elsif($verbose>=1 and ($val < 0.2 or $val > 3)){print "WARNING: $str = $val - Typical range is [0.2,3].\n"}
    
    $str = "horizHalfWidthFt"; $val = $rps->{stream}{$str};
    if ($val <= 0){$ok=0; print "ERROR: $str = $val - Must be must be positive.\n"}
    elsif($verbose>=1 and ($val < 3 or $val > 20)){print "WARNING: $str = $val - Typical range is [3,20].\n"}
    
    $str = "horizHalfWidthFt"; $val = $rps->{stream}{$str};
    if ($val < 2 and $val != 0){$ok=0; print "ERROR: $str = $val - Must be must be either 0 or greater than or equal to 2.\n"}
    elsif($verbose>=1 and ($val < 2 or $val > 10)){print "WARNING: $str = $val - Typical range is [2,10].\n"}
    

    
    $str = "crossStreamAngle"; $val = eval($rps->{configuration}{$str});
    if ($val <= -$pi or $val >= $pi){$ok=0; print "ERROR: $str = $val - cross stream angle must be in the range (-pi,pi).\n"}
    elsif($verbose>=1 and ($val < 0 or $val > $pi/2)){print "WARNING: $str = $val - Typical range is [-pi\/2,pi\/2].\n"}
    
    $str = "curvatureInvFt"; $val = eval($rps->{configuration}{$str});
    if (abs($val) > 2/$rps->{line}{activeLenFt}){$ok=0; print "ERROR: $str = $val - line initial curvature must be in the range (-2\/activeLen,2\/activeLen).\n"}
    
    $str = "preStretchMult"; $val = $rps->{configuration}{$str};
    if ($val < 1){$ok=0; print "ERROR: $str = $val - Must be no less than 1.\n"}
    elsif($verbose>=1 and ($val < 1.001 or $val > 1.1)){print "WARNING: $str = $val - Typical range is [1.001,1.1].\n"}
    
    $str = "tuckHeightFt"; $val = $rps->{configuration}{$str};
    if ($val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val > 10)){print "WARNING: $str = $val - Typical range is [0,10].\n"}
    
    $str = "tuckVelFtPerSec"; $val = $rps->{configuration}{$str};
    if ($val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val > 10)){print "WARNING: $str = $val - Typical range is [0,10].\n"}
    
    
    $str = "laydownIntervalSec"; $val = $rps->{driver}{$str};
    if ($val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val > 1)){print "WARNING: $str = $val - Typical range is [0,1].\n"}
    
    $str = "startCoordsFt";
    my $ss = Str2Vect($rps->{driver}{$str});
    if ($ss->nelem != 3) {
        $ok=0;
        print "ERROR: $str must be of the form X,Y,Z.\n";
    } else {
        $a = $ss(0); $b = $ss(1); $c = $ss(2);
        if ($verbose>=1 and (abs($a) > 15 or abs($b)>15 or abs($c)>15)){print "WARNING: $str = $a,$b,$c - Typical values are less than an arm plus rod length.\n"}
    }
    
    $str = "endCoordsFt";
    my $ee = Str2Vect($rps->{driver}{$str});
    if ($ee->nelem != 3) {
        $ok=0;
        print "ERROR: $str must be of the form X,Y,Z.\n";
    } else {
        $a = $ee(0); $b = $ee(1); $c = $ee(2);
        if ($verbose>=1 and (abs($a) > 15 or abs($b)>15 or abs($c)>15)){print "WARNING: $str = $a,$b,$c - Typical absolute values are less than an arm plus rod length.\n"}
    }
    
    $str = "pivotCoordsFt";
    my $ff = Str2Vect($rps->{driver}{$str});
    if ($ff->nelem != 3) {
        $ok=0;
        print "ERROR: $str must be of the form X,Y,Z.\n";
    } else {
        $a = $ff(0); $b = $ff(1); $c = $ff(2);
        if ($c<0){$ok=0; print "ERROR: $str = $val - Pivot Z coord must be non-negative.\n"}
        elsif($verbose>=1 and (abs($a) > 0 or abs($b)>0 or $c>6)){print "WARNING: $str = $a,$b,$c - Typical X and Y coords are zero and Z about 5.\n"}
    }
    
    my $tLen = sqrt(sumover(($ee-$ss)**2));
    $str = "trackCurvatureInvFt"; $val = eval($rps->{driver}{$str});
    if (abs($val) > 2/$tLen){$ok=0; print "ERROR: $str = $val - track curvature must be in the range (-2\/trackLen,2\/trackLen).\n"}
    
    $str = "trackSkewness"; $val = $rps->{driver}{$str};
    if($verbose>=1 and ($val < -0.25 or $val > 0.25)){print "WARNING: $str = $val - Positive values peak later.  Typical range is [-0.25,0.25].\n"}

    if ($rps->{driver}{startTime} >= $rps->{driver}{endTime}){print "WARNING:  motion start time greater or equal to motion end time means no rod tip motion will happen.\n"}
    
    $str = "velocitySkewness"; $val = $rps->{driver}{$str};
    if($verbose>=1 and ($val < -0.25 or $val > 0.25)){print "WARNING: $str = $val - Positive values peak later.  Typical range is [-0.25,0.25].\n"}
    
 
    $str = "numSegs"; $val = $rps->{integration}{$str};
    if ($val < 1 or ceil($val) != $val){$ok=0; print "ERROR: $str = $val - Must be an integer >= 1.\n"}
    elsif($verbose>=1 and ($val > 31)){print "WARNING: $str = $val - Typical range is [11,31].\n"}
    
    $str = "segExponent"; $val = $rps->{integration}{$str};
    if ($val <= 0){$ok=0; print "ERROR: $str = $val - Seg exponent must be positive.\n"}
    elsif($verbose>=1 and ($val < 0.5 or $val > 2)){print "WARNING: $str = $val - Typical range is [0.5,2].\n"}
    
    $str = "t0"; $val = $rps->{integration}{$str};
    if ($val < 0){$ok=0; print "ERROR: $str = $val - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val != 0)){print "WARNING: $str = $val - Usually 0.\n"}
    
    $str = "t1"; $val = $rps->{integration}{$str};
    if ($val <= $rps->{integration}{t0}){$ok=0; print "ERROR: $str = $val - Must larger than t0.\n"}
    elsif($verbose>=1 and ($val > 10)){print "WARNING: $str = $val - Usually less than 10.\n"}
    
    $str = "dt0"; $val = $rps->{integration}{$str};
    if ($val <= 0){$ok=0; print "ERROR: $str = $val - Must be positive.\n"}
    elsif($verbose>=1 and ($val > 1e-4 or $val < 1e-7)){print "WARNING: $str = $val - Typical range is [1e-4,1e-7].\n"}
   
    my $test = 1/6;
    $str = "plotDt"; $val = eval($rps->{integration}{$str});
    if ($val <= 0){$ok=0; print "ERROR: $str = $val - Must be positive.\n"}
    elsif($verbose>=1 and ($val < $test or $val > 1)){print "WARNING: $str = $val - Typical range is [1/6,1].\n"}
    
    $str = "plotZScale"; $val = $rps->{integration}{$str};
    if ($val < 1){$ok=0; print "ERROR: $str = $val - Magnification must be no less than 1.\n"}
    elsif($verbose>=1 and ($val > 5)){print "WARNING: $str = $val - Typical range is [1/5].\n"}
    
    $str = "verbose"; $val = $rps->{integration}{$str};
    if ($val < 0 or ceil($val) != $val){$ok=0; print "ERROR: $str = $val - Must be a non-negative integer.\n"}
    elsif(DEBUG and $verbose>=1 and ($val > 6)){print "WARNING: $str = $val - Typical range is [0,6].  Higher values print more diagnostic material.\n"}
    elsif(!DEBUG and $verbose>=1 and ($val > 3)){print "WARNING: $str = $val - Unless compiled in DEBUG mode, effective range is [0,3].  Higher values (<= 3) print more diagnostic material.\n"}
    return $ok;
}


my $flyLineNomWtGrPerFt;
my ($leaderStr,$lineLenFt,$leaderLenFt,$tippetLenFt);
my ($loadedLenFt,$loadedGrsPerFt,$loadedDiamsIn,$loadedElasticDiamsIn,$loadedElasticModsPSI,$loadedDampingDiamsIn,$loadedDampingModsPSI,$loadedBuoyGrsPerFt);


my ($leaderElasticModPSI,$leaderDampingModPSI,$tippetElasticModPSI,$tippetDampingModPSI);
my $tippetStr;

my $loadedState = zeros(0); # Disable for now.  Continuing a previously saved run, see RHexCastPkg.
my $loadedLineSegLens;

sub LoadLine {
    my ($lineFile) = @_;
    
    ## Process lineFile if defined, otherwise set line from defaults.
    
    PrintSeparator("Loading line");
    
    my $ok = 1;
    
    $flyLineNomWtGrPerFt    = $rps->{line}{nomWtGrsPerFt};
    $loadedGrsPerFt         = zeros(0);
    
    if ($lineFile) {
        
        if ($verbose>=1){print "Data from $lineFile.\n"}
        
        $/ = undef;
        #        open INFILE, "< $lineFile" or die $!;
        open INFILE, "< $lineFile" or $ok = 0;
        if (!$ok){print "ERROR: $!\n";return 0}
        my $inData = <INFILE>;
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
                    my $density = $rps->{line}{estimatedDensity};
                    my $weights = $loadedGrsPerFt/($grPerOz*12); # Ounces/inch
                    my $displacements   = $weights/$waterOzPerIn3;  # inches**2;
                    my $vols            = $displacements/$density;
                    $loadedDiamsIn      = sqrt($vols);
                    #pq($density,$weights,$displacements,$vols);
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


my $elasticModPSI_Nylon = 2.1e5;
my $DampingModPSI_Dummy;

my $leaderIdentifier;

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
        
        $/ = undef;
        #        open INFILE, "< $lineFile" or die $!;
        open INFILE, "< $leaderFile" or $ok = 0;
        if (!$ok){print "ERROR: $!\n";return 0}
        my $inData = <INFILE>;
        close INFILE;
        
        if ($inData =~ m/^Identifier:\t(\S*).*\n/mo)
        {$leaderIdentifier = $1; }
        if ($verbose>=2){print "leaderID = $leaderIdentifier\n"}
        
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
            my $materialStr = GetQuotedStringFromDataString($inData,"Material");
            if (defined($materialStr)){
                #pq($materialStr);
            
                switch ($materialStr) {
                    case "mono"     {$leaderSpecGravity = 1.01}
                    case "fluoro"   {$leaderSpecGravity = 1.85}
                    else {
                        print "ERROR:  The only recognized leader materials are \"mono\" and \"fluoro\".\n";
                        $materialStr = undef;
                    }
                }
            }
            if (!defined($materialStr)){

                # Look for SpecificGravity field:
                $leaderSpecGravity = GetValueFromDataString($inData,"SpecificGravity");
                if (!defined($leaderSpecGravity)){$leaderSpecGravity = 1.1} # Presume mono.
            }
            
            # Compute diams from
            if ($verbose){printf("Computing leader diameters from weights and specific gravity=%.2f (material presumed to be mono if not otherwise deducible).\n",$leaderSpecGravity)}
            
            my $weights         = $leaderGrsPerFt/($grPerOz*12); # Ounces/inch
            my $displacements   = $weights/$waterOzPerIn3;  # inches**2;
            my $vols            = $displacements/$leaderSpecGravity;
            $leaderDiamsIn      = sqrt($vols);
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
            else    {die "\n\nDectected unimplemented leader text ($leaderStr).\n\n"}
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
    
    my $tippetVolsIn3           = 12*($pi/4)*$tippetDiamsIn**2;
    pq($tippetVolsIn3);
    my $tippetGrsPerFt          =
        $specGravity * $waterOzPerIn3 * $grPerOz * $tippetVolsIn3 * ones($tippetLenFt);
    
    my $waterGrPerIn3 = $waterOzPerIn3*$grPerOz;
    pq($specGravity,$waterGrPerIn3,$tippetGrsPerFt);
    
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
    
    
    # Figure the buoyancies, and densities as a test.
    #pq($loadedGrsPerFt);
    #my $loadedOzPerFt   = $loadedGrsPerFt/$grPerOz;
    my $loadedAreasIn2  = ($pi/4)*$loadedDiamsIn**2;
    my $loadedVolsPerFt = 12*$loadedAreasIn2;   # number of inches cubed.
    #my $loadedBuoyOzPerFt = $loadedVolsPerFt*$waterOzPerIn3;
    #my $loadedDensities = $loadedOzPerFt/$loadedBuoyOzPerFt;
    #pq($loadedDensities);
    
    $loadedBuoyGrsPerFt = $loadedVolsPerFt*($waterOzPerIn3*$grPerOz);
    my $loadedDensities = $loadedGrsPerFt/$loadedBuoyGrsPerFt;
    if ($verbose>=3){pq($loadedBuoyGrsPerFt,$loadedDensities)}    
}


my ($driverIdentifier,$driverStr);
my ($driverXs,$driverYs,$driverZs);  # pdls.
my ($timeXs,$timeYs,$timeZs);  # pdls.
my $frameRate;
my $integrationStr;


sub LoadDriver {
    my ($driverFile) = @_;
    
    my $ok = 1;
    ## Process castFile if defined, otherwise set directly from cast params --------
    
    # Unset cast pdls (to empty rather than undef):
    ($driverXs,$driverYs,$driverZs,$timeXs,$timeYs,$timeZs) = map {zeros(0)} (0..5);
    
    
    # The cast drawing is expected to be in SVG.  See http://www.w3.org/TR/SVG/ for the full protocol.  SVG does 2-DIMENSIONAL drawing only! See the function SVG_matrix() below for the details.  Ditto resplines.
    
    PrintSeparator("Loading rod tip motion");
    
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
            
            die "Not yet implemented in 3D.\n";
            
            # Look for the "DriverSplines" identifier in the file:
            if ($inData =~ m[XPath]){
                if (!LoadDriverFromPathSVG($inData)){$ok=0;goto BAD_RETURN};
            } else {
                if (!LoadDriverFromHandleVectorsSVG($inData)){$ok=0;goto BAD_RETURN}
            }
        } elsif ($ext eq ".txt"){
            if (!LoadDriverFromPathTXT($inData)){$ok=0;goto BAD_RETURN};
        } else {  print "ERROR: Rod tip motion file must have .txt or .svg extension"; return 0}
        
    } else {
        if ($verbose>=2){print "No file.  Setting rod tip motion from Widget params.\n"}
        SetDriverFromParams();
        $driverIdentifier = "Parameterized";
    }
    
    # A base track is now in place.  Apply further curvature and theta adjustments as desired:
    if ($rps->{driver}{adjustEnable}) {
        AdjustCast();
    }
    
BAD_RETURN:
    if (!$ok){print "LoadCast DETECTED ERRORS.\n"}
    
    return $ok;
}


my $numDriverTimes = 21;
my $driverSmoothingFraction = 0.2;
my ($driverStartTime,$driverEndTime);


sub LoadDriverFromPathTXT {
    my ($inData) = @_;
    
    ## Blah:
    
    my $ok = 1;
    
    if ($inData =~ m/^Identifier:\t(\S*).*\n/mo)
    {$driverIdentifier = $1; }
    if ($verbose>=2){print "driverID = $driverIdentifier\n"}
    
    $driverStartTime = GetValueFromDataString($inData,"StartTime");
    if (!defined($driverStartTime)){$ok = 0; print "ERROR: StartTime not found in driver file.\n"}
    if ($verbose>=3){pq($driverStartTime)}
    
    my $tOffsets = GetMatFromDataString($inData,"TimeOffsets");
    if ($tOffsets->isempty){$ok = 0; print "ERROR: TimeOffsets not found in driver file.\n"}
    if (DEBUG and $verbose>=4){pq($tOffsets)}
    
    my $xStart = GetValueFromDataString($inData,"StartX");
    if (!defined($xStart)){$ok = 0; print "ERROR: StartX not found in driver file.\n"}
    if (DEBUG and $verbose>=4){pq($xStart)}
    
    my $xOffsets = GetMatFromDataString($inData,"XOffsets");
    if ($xOffsets->isempty){$ok = 0; print "ERROR: XOffsets not found in driver file.\n"}
    if (DEBUG and $verbose>=4){pq($xOffsets)}
    
    my $yStart = GetValueFromDataString($inData,"StartY");
    if (!defined($yStart)){$ok = 0; print "ERROR: StartY not found in driver file.\n"}
    if (DEBUG and $verbose>=4){pq($yStart)}
    
    my $yOffsets = GetMatFromDataString($inData,"YOffsets");
    if ($yOffsets->isempty){$ok = 0; print "ERROR: YOffsets not found in driver file.\n"}
    if (DEBUG and $verbose>=4){pq($yOffsets)}
    
    my $zStart = GetValueFromDataString($inData,"StartZ");
    if (!defined($zStart)){$ok = 0; print "ERROR: StartZ not found in driver file.\n"}
    if (DEBUG and $verbose>=4){pq($zStart)}
    
    my $zOffsets = GetMatFromDataString($inData,"ZOffsets");
    if ($zOffsets->isempty){$ok = 0; print "ERROR: ZOffsets not found in driver file.\n"}
    if (DEBUG and $verbose>=4){pq($zOffsets)}
    
    if (!$ok){ return $ok}
    
    $timeXs = $driverStartTime+$tOffsets;
    $timeYs = $timeXs;
    $timeZs = $timeXs;
    
    $driverEndTime = $timeXs(-1)->sclr;
    
    $driverXs   = ($xStart+$xOffsets)*12;
    $driverYs   = ($yStart+$yOffsets)*12;
    $driverZs   = ($zStart+$zOffsets)*12;
    
    if ($verbose>=3){pq($driverEndTime,$driverXs,$driverYs,$driverZs)}
    
    if ($rps->{driver}{showTrackPlot}){
        Plot3D($driverXs/12,$driverYs/12,$driverZs/12,"Rod Tip Track");
    }
    
    return $ok;
}


sub SetDriverFromParams {
    
    ## If driver was not already read from a file, construct a normalized one on a linear base here from the widget's track params:
    
    my $coordsStart = Str2Vect($rps->{driver}{startCoordsFt})*12;        # Inches.
    my $coordsEnd   = Str2Vect($rps->{driver}{endCoordsFt})*12;
    my $coordsPivot = Str2Vect($rps->{driver}{pivotCoordsFt})*12;
    
    my $curvature   = eval($rps->{driver}{trackCurvatureInvFt})/12;   # 1/Inches.
    my $length      = sqrt(sumover(($coordsEnd - $coordsStart)**2));
    
    $driverStartTime    = $rps->{driver}{startTime};
    $driverEndTime      = $rps->{driver}{endTime};
    if ($verbose>=3){pq($driverStartTime,$driverEndTime)}
    
    if ($driverStartTime >= $driverEndTime or $length == 0){  # No rod tip motion
        
        ($driverXs,$driverYs,$driverZs) = map {ones(2)*$coordsStart($_)} (0..2);
        ($timeXs,$timeYs,$timeZs)       = map {sequence(2)} (0..2);     # KLUGE:  Spline interpolation requires at least 2 distinct time values.
        return;
    }
    
    my $totalTime = $driverEndTime-$driverStartTime;
    my $times = $driverStartTime + sequence($numDriverTimes)*$totalTime/($numDriverTimes-1);
    
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
        $unitTrack      /= sqrt(sumover($unitTrack**2));
        
        #pq($length,$curvature,$refVect,$unitTrack);
        
        my $unitDisplacement    = $refVect - sumover($refVect*$unitTrack)*$unitTrack;
        $unitDisplacement      /= sqrt(sumover($unitDisplacement**2));
        
        my $xs  = sqrt(sumover(($coords-$coordsStart)**2));   # Turned into a flat vector.
        
        my $skewExponent = $rps->{driver}{trackSkewness};
        if ($skewExponent){
            $xs = SkewSequence(0,$length,$skewExponent,$xs);
        }
        
        my $secantOffsets = SecantOffsets(1/$curvature,$length,$xs);     # Returns a flat vector.
        #pq($secantOffsets);
        
        
        $coords += $secantOffsets->transpose x $unitDisplacement;
        #pq($coords);
    }

    #pq($coords);
    #die;
    
    ($driverXs,$driverYs,$driverZs)   = map {$coords($_,:)->flat} (0..2);
    pq($coords);
    
    my $velExponent = $rps->{driver}{velocitySkewness};
    if ($velExponent){
        pq($times);
        $times = SkewSequence($driverStartTime,$driverEndTime,-$velExponent,$times);
        # Want positive to mean fast later.
    }
    
    
    $timeXs = $times;
    $timeYs = $times;
    $timeZs = $times;
    
    if ($rps->{driver}{showTrackPlot}){
        Plot3D($driverXs/12,$driverYs/12,$driverZs/12,"Rod Tip Track");
    }
}


my $numSegs;
my ($segWts,$segLens,$segCGs,$segCGDiams,$segBuoys);
my ($segCGElasticDiamsIn,$segCGElasticModsPSI,$segCGDampingDiamsIn,$segCGDampingModsPSI);
my ($flyWt,$flyBuoy,$flyNomLen,$flyNomDiam,$flyNomDispVol);
my ($lineSegLens,$lineTipOffset,$leaderTipOffset);
my ($activeLen,$lineSegNomLens);


sub SetupModel {
    
    ## Called just prior to running. Convert the line file data to a specific model for use by the solver.
    
    PrintSeparator("Setting up model");
    
    if ($loadedState->isempty){
        
        $numSegs       = $rps->{integration}{numSegs};
        $lineSegNomLens = zeros(0);
        # Nominal because we will later deal with stretch.
        
    } else{
        
        die;    # Not yet implemented.
        $numSegs               = $loadedLineSegLens->nelem;
        $rps->{integration}{numSegs}  = $numSegs;   # Show the user.
        $lineSegNomLens         = $loadedLineSegLens;
    }
    
    
    # Work first with the true segs.  Will deal with the fly pseudo-segment later.
    # For compatibility with RHCast, does NOT include the rod tip node.
    
    my $activeLenFt = $rps->{line}{activeLenFt};
    $activeLen   = 12 * $activeLenFt;
    
    $lineLenFt = $activeLenFt - $leaderLenFt - $tippetLenFt;
    
    $leaderTipOffset    = $tippetLenFt*12;  # inches
    $lineTipOffset      = $leaderTipOffset + $leaderLenFt*12;
    
    my $fractNodeLocs;
    if ($lineSegNomLens->isempty) {
        $fractNodeLocs = sequence($numSegs+1)**$rps->{integration}{segExponent};
    } else {
        $fractNodeLocs = cumusumover(zeros(1)->glue(0,$lineSegNomLens));
    }
    $fractNodeLocs /= $fractNodeLocs(-1);
    if (DEBUG and $verbose>=4){pq($fractNodeLocs)}
    
    my $nodeLocs    = $activeLen*$fractNodeLocs;
    if ($verbose>=3){pq($nodeLocs)}

    
    # Figure the segment weights -------

    # Take just the active part of the line, leader, tippet.  Low index is TIP:
    my $lastFt  = POSIX::floor($activeLenFt);
    #pq ($lastFt,$totalActiveLenFt,$loadedGrsPerFt);
    
    my $availFt = $loadedGrsPerFt->nelem;
    if ($lastFt >= $availFt){die "Active length (sum of line outside rod tip, leader, and tippet) requires more fly line than is available in file.  Set shorter active len or load a different line file.\n"}
    
    my $activeLineGrs   =  $loadedGrsPerFt($lastFt:0)->copy;    # Re-index to start at rod tip.
    my $nodeGrs         = ResampleVectLin($activeLineGrs,$fractNodeLocs);
    my $segGrs          = ($nodeGrs(0:-2)+$nodeGrs(1:-1))/2;
    if (DEBUG and $verbose>=4){pq($activeLineGrs,$nodeGrs,$segGrs)}
    
    $segCGs = $nodeGrs(1:-1)/($nodeGrs(0:-2)+$nodeGrs(1:-1));
    $segWts = $segGrs/$grPerOz;
    if ($verbose>=3){pq($segCGs,$segWts)}
    # Ounces attributed to each line segment.

    my $activeLineBuoyGrs   =  $loadedBuoyGrsPerFt($lastFt:0)->copy;    # Re-index to start at rod tip.
    my $nodeBuoyGrs         = ResampleVectLin($activeLineBuoyGrs,$fractNodeLocs);
    my $segBuoyGrs          = ($nodeBuoyGrs(1:-1)+$nodeBuoyGrs(0:-2))/2;
    if (DEBUG and $verbose>=4){pq($activeLineBuoyGrs,$nodeBuoyGrs,$segBuoyGrs)}

    $segBuoys           = $segBuoyGrs/$grPerOz;
    my $segDensities    = $segWts/$segBuoys;
    if ($verbose>=3){pq($segBuoys,$segDensities)}
    
    # Figure the seg lengths.
    $segLens            = $nodeLocs(1:-1)-$nodeLocs(0:-2);
    if ($verbose>=3){pq($segLens)}

    my $activeDiamsIn   =  $loadedDiamsIn($lastFt:0)->copy;    # Re-index to start at rod tip.
    my $fractCGs        = (1-$segCGs)*$fractNodeLocs(0:-2)+$segCGs*$fractNodeLocs(1:-1);
    if (DEBUG and $verbose>=4){pq($activeDiamsIn,$fractCGs)}
    
    $segCGDiams         = ResampleVectLin($activeDiamsIn,$fractCGs);
        # For the line I will compute Ks and Cs based on the diams at the segCGs.
    if ($verbose>=3){pq($segCGDiams)}
    

    my $activeElasticDiamsIn =  $loadedElasticDiamsIn($lastFt:0)->copy;
    my $activeElasticModsPSI =  $loadedElasticModsPSI($lastFt:0)->copy;
    my $activeDampingDiamsIn =  $loadedDampingDiamsIn($lastFt:0)->copy;
    my $activeDampingModsPSI =  $loadedDampingModsPSI($lastFt:0)->copy;

    $segCGElasticDiamsIn    = ResampleVectLin($activeElasticDiamsIn,$fractCGs);
    $segCGElasticModsPSI    = ResampleVectLin($activeElasticModsPSI,$fractCGs);
    $segCGDampingDiamsIn    = ResampleVectLin($activeDampingDiamsIn,$fractCGs);
    $segCGDampingModsPSI    = ResampleVectLin($activeDampingModsPSI,$fractCGs);
    if ($verbose>=3){pq($segCGElasticDiamsIn,$segCGElasticModsPSI,$segCGDampingDiamsIn,$segCGDampingModsPSI)}
    
    # Set the fly specs -------------
    
    $flyWt          = $rps->{fly}{wtGr}/$grPerOz;
    $flyNomLen      = $rps->{fly}{nomLenIn};
    $flyNomDiam     = $rps->{fly}{nomDiamIn};
    
    $flyNomDispVol  = $rps->{fly}{nomDispVolIn3};
    $flyBuoy        = $flyNomDispVol*$waterOzPerIn3;
    my $flyDens = ($flyWt >0 and $flyBuoy == 0) ? $inf : $flyWt/$flyBuoy;
    if ($verbose>=3){pq($flyDens)}
    
    if ($verbose>=2){pq($flyWt,$flyBuoy,$flyNomLen,$flyNomDiam)}
    
    my $activeWt = sumover($segWts)+pdl($flyWt);
    if ($verbose>=2){pq($activeWt)}
    
}


my ($driverTotalTime);
my ($driverXSpline,$driverYSpline,$driverZSpline);


sub SetupDriver {
    
    ## Prepare the external constraint at the rod tip.  Applied during integration by Calc_Driver().
    
    PrintSeparator("Setting up rod tip driver");
    
    # Set up spline interpolations, so that during integration we can just eval.
    if (!defined($timeXs) or !$timeXs->nelem){   # Not loaded from PathSVG, so all the same:
        $frameRate  = $rps->{driver}{frameRate};
        $timeXs     = ($driverXs->sequence)/$frameRate;
        $timeYs     = $timeXs;  # no need to make copies.
        $timeZs     = $timeXs;
        if (DEBUG and $verbose>=4){pq $timeXs}
        
        my $bcFrames = POSIX::ceil($rps->{driver}{boxcarFrames});
        if ($bcFrames>1){
            $driverXs   = BoxcarVect($driverXs,$bcFrames);
            $driverYs   = BoxcarVect($driverYs,$bcFrames);
            $driverZs   = BoxcarVect($driverZs,$bcFrames);
        }
    }
    
    my $tEnds = pdl($timeXs(-1)->sclr,$timeYs(-1)->sclr,$timeZs(-1)->sclr);
    # If they came from resplining, they might be a tiny bit different.
    $driverTotalTime = $tEnds->min;     # Used globally.
    if (DEBUG and $verbose>=4){pq $driverTotalTime}
    
    # Interpolate in arrays, all I have for now:
    my @aTimeXs = list($timeXs);
    my @aTimeYs = list($timeYs);
    my @aTimeZs = list($timeZs);
    
    my @aDriverXs   = list($driverXs);
    my @aDriverYs   = list($driverYs);
    my @aDriverZs   = list($driverZs);
    
    $driverXSpline = Math::Spline->new(\@aTimeXs,\@aDriverXs);
    $driverYSpline = Math::Spline->new(\@aTimeYs,\@aDriverYs);
    $driverZSpline = Math::Spline->new(\@aTimeZs,\@aDriverZs);
    
    # Plot the driver with enough points in each segment to show the spline behavior:
    #    if ($rps->{driver}{plotSplines}){
    
    if ($rps->{driver}{showTrackPlot} and $verbose>=3){
        PlotDriverSplines(101,$driverXSpline,$driverYSpline,$driverZSpline);
    }
    
    # Set driver string:
    my $tTT = sprintf("%.3f",$driverTotalTime);
    my $tT0 = sprintf("%.3f",sclr($driverZs(0)));
    my $tT1 = sprintf("%.3f",sclr($driverZs(-1)));
    
    $integrationStr = "DRIVER: ID=$driverIdentifier;  INTEGRATION: t=($rps->{integration}{t0}:$rps->{integration}{t1}:$rps->{integration}{plotDt}); $rps->{integration}{stepperName}; t=(0,$tTT)";
    
    if ($verbose>=2){pq $integrationStr}
}



my ($segStartTs,$iSegStart);

sub SetSegStartTs {
    my ($t0,$sinkIntervalSec,$stripRateFtPerSec,$lineSegLens,$shortStopInterval) = @_;
    
    ## Set the times of the scheduled, typically irregular, events that mark a change in integrator behavior.

    PrintSeparator("Setting up seg start t\'s");

    if ($stripRateFtPerSec){
        
        my $tIntervals = pdl($sinkIntervalSec)->glue(0,$lineSegLens/$stripRateFtPerSec);
        $segStartTs = cumusumover($tIntervals);
        
        if ($shortStopInterval){
            $segStartTs(1:-1) -= $shortStopInterval;
        }
    }
    else {
        $segStartTs = zeros(0);
    }
    
    if ($verbose>=3){pq($segStartTs)}
    
    return $segStartTs;
}



my ($qs0,$qDots0);

sub SetStartingConfig {
    my ($lineSegLens) = @_;
    
    ## Take the initial line configuration as straight and horizontal, deflected from straight downstream by the specified angle (pos is toward the plus Y-direction).
    
    PrintSeparator("Setting up starting configuration");
    
    my $lineTheta0  = eval($rps->{configuration}{crossStreamAngle});   # ?? direction ??
    my $lineCurve0  = eval($rps->{configuration}{curvatureInvFt})/12;   # 1/in
    
    my ($dxs0,$dys0) = RelocateOnArc($segLens,$lineCurve0,$lineTheta0);
    
    my $dzs0 = zeros($dxs0);
    if ($verbose>=3){pq($dxs0,$dys0,$dzs0)}
    
    my $qs0 = $dxs0->glue(0,$dys0)->glue(0,$dzs0);
    if (DEBUG and $verbose>=4){pq($lineTheta0)}
    
    return ($qs0,zeros($qs0));  # Zero the initial velocities.
    
    #If 0, try to use initial line configuration from file.  If a second value is given, it the inital line shape to a #constant curve having that value as radius of curvature.
}



sub AdjustStartingForTuck {
    my ($tuckHtIn,$tuckVelInPerSec,$segLens) = @_;
    
    # Adjust the $qs0 and $qDots0 in place.

    PrintSeparator("Adjusting for tuck");

    if ($verbose>=3){pq($qs0,$qDots0)}
    
    my $numSegs = $segLens->nelem;
    
    my $dxs = $qs0(0:$numSegs-1);
    my $dys = $qs0($numSegs:2*$numSegs-1);
    my $dzs = $qs0(2*$numSegs:-1);
    pq($dxs,$dys,$dzs);
    
    
    my $tippetLen   = $rps->{tippet}{lenFt}*12;
    my $cumLens     = cumusumover($segLens);
    my $totalLen    = $cumLens(-1);
    #pq($tippetLen,$cumLens,$totalLen);
    my $indsTippet  = which($cumLens >= $totalLen-$tippetLen);   # Never empty.
    #pq($indsTippet);
    
    # Collect all the tippet nodes at the last leader node:
    $dxs($indsTippet)   .= 0;
    $dys($indsTippet)   .= 0;
    #pq($dxs,$dys);
    
    # Ramp up the dzs:
    my $firstTippetInd  = sclr($indsTippet(0));  # So following sequence() works.
    my $lastLineInd     = $firstTippetInd-1;    # Line plus leader, actually.
    my $numTippetInds   = $indsTippet->nelem;
    pq($firstTippetInd);

    
    my $dZs = ($tuckHtIn/$firstTippetInd) * ones($firstTippetInd);
    pq($dZs);
    #$dZs    /= $dZs(-1);    # Normalize
   # pq($dZs);
    #$dZs    *= $tuckHtIn;
    #pq($dZs);
    $dZs    = $dZs->glue(0,zeros($indsTippet));
    pq($dZs);
   
    $dzs    += $dZs;
    #pq($dzs);
    
    # Now, readjust the dxs and dys to make the segLens right:
    my $lineDxs     = $dxs(0:$lastLineInd);
    my $lineDys     = $dys(0:$lastLineInd);
    my $oldLineDrs  = sqrt($lineDxs**2 + $lineDys**2);
    pq($oldLineDrs);

    my $lineDzs     = $dzs(0:$lastLineInd);
    my $lineSegLens = $segLens(0:$lastLineInd);
    pq($lineDzs,$lineSegLens);
    
    my $newLineDrs  = sqrt($lineSegLens**2 - $lineDzs**2);
    my $mults    = $newLineDrs/$oldLineDrs;
    pq($newLineDrs,$mults);
    $lineDxs *= $mults;
    $lineDys *= $mults;
    pq($lineDxs,$lineDys);
    
    pq($dxs,$dys,$dzs);
    
    # Check:
    my $finalDrs = sqrt($dxs**2+$dys**2+$dzs**2);
    pq($finalDrs,$segLens);
    
    # Give the tippet segs a negative z-velocity:
    my $tippetVels  = sequence($indsTippet)+1;
    $tippetVels     *= -$tuckVelInPerSec/$tippetVels(-1);
    pq($tippetVels);
    $indsTippet     = -$indsTippet(-1)+$indsTippet-1;
    pq($indsTippet);
    
    $qDots0(-$numTippetInds:-1)    .= $tippetVels;
    #$qDots0($indsTippet)    .= $tippetVels;       # Surprisingly, interpreter chokes on this.
    
    if ($verbose>=3){pq($qs0,$qDots0)}

    return ($qs0,$qDots0);
}



my ($profileStr,$paramsStr);
my ($lineCoreDiamIn);
my ($dragSpecsNormal,$dragSpecsAxial);
my ($sinkInterval,$stripRate);
my $timeStr;
my ($T,$Dynams,$Dynams0,$dT);
my $shortStopInterval = 0.00;   # Secs.  This mechanism doesn't seem necessary.  See Hamilton::AdjustTrack_STRIPPING().
my %opts_plot;
my $surfaceVelFtPerSec;
my $levelLeaderSink;

sub SetupIntegration {
    
    ## Convert component data to a specific model for use by the fitting function.  Call this function when (re)loading the data as soon as $rps is set, to prepare for calculating the flex.
    
    $timeStr = scalar(localtime);
    
    my($date,$time) = ShortDateTime;
    my $dateTimeShort = sprintf("(%06d_%06d)",$date,$time);
    
    $rps->{file}{save} = '_'.$rps->{line}{identifier}.'_'.$dateTimeShort;
    
    $profileStr     = $rps->{stream}{profileText};
    $profileStr     = substr($profileStr,10); # strip off "profile - "

    
    my $bottomDepthFt           = $rps->{stream}{bottomDepthFt};
    $surfaceVelFtPerSec         = $rps->{stream}{surfaceVelFtPerSec};   # Sic, global
    my $halfVelThicknessFt      = $rps->{stream}{halfVelThicknessFt};
    my $surfaceLayerThicknessIn = $rps->{stream}{surfaceLayerThicknessIn};
    
    my $horizHalfWidthFt        = $rps->{stream}{horizHalfWidthFt};
    my $horizExponent           = $rps->{stream}{horizExponent};
    
    # Show the velocity profile:
    if ($rps->{stream}{showProfile}){
        #        my $count = 101; my $Ys = -(sequence($count+5)/($count-1))*$bottomDepthFt*12;
        my $count   = 101;
        my $Zs      = ((10-sequence($count+15))/($count-1))*$bottomDepthFt*12;
        
        Calc_VerticalProfile($Zs,$profileStr,$bottomDepthFt,$surfaceVelFtPerSec,$halfVelThicknessFt,$surfaceLayerThicknessIn,1);
        
        my $Ys  = (sequence(2*$count+1)-$count)/$count;
        $Ys     *= 2* $horizHalfWidthFt*12;     # first arg is inches.
        
        Calc_HorizontalProfile($Ys,$horizHalfWidthFt,$horizExponent,1);
    }
    
    
    # Build the active Ks and Cs:
    my $elasticAreas    = ($pi/4)*$segCGElasticDiamsIn**2;
    my $elasticMods     = $segCGElasticModsPSI * 16;    # Oz per sq in.
    
    my $segKs = $elasticMods*$elasticAreas/$segLens;      # Oz to stretch 1 inch.
        # Basic Hook's law, on just the level core, which contributes most of the stretch resistance.

    my $dampingAreas    = ($pi/4)*$segCGDampingDiamsIn**2;
    my $dampingMods     = $segCGDampingModsPSI * 16;    # Oz per sq in.
    
    my $segCs = $dampingMods*$dampingAreas/$segLens;      # Oz to stretch 1 inch.
    # By analogy with Hook's law, on the whole diameter. Figure the elongation damping coefficients USING FULL LINE DIAMETER since the plastic coating probably contributes significantly to the stretching friction.

    if ($verbose>=3){pq($segKs,$segCs)}

    
    my $gravity = $rps->{ambient}{gravity};
    
    # Setup drag for the line segments:
    $dragSpecsNormal    = Str2Vect($rps->{ambient}{dragSpecsNormal});
    $dragSpecsAxial     = Str2Vect($rps->{ambient}{dragSpecsAxial});
    
    # Calculate and print free sink speed:
    if ($leaderStr eq "level"){
        my $levelDiamIn = $rps->{leader}{diamIn};
        my $levelLenIn  = 12;
        my $levelWtsOz  = $rps->{leader}{wtGrsPerFt}/$grPerOz;
        $levelLeaderSink =
            Calc_FreeSinkSpeed($dragSpecsNormal,$levelDiamIn,$levelLenIn,$levelWtsOz);
        printf("Calculated free sink speed of level leader is %.3f (in\/sec).\n",$levelLeaderSink);

    } else { $levelLeaderSink = undef}
    
    $sinkInterval       = eval($rps->{driver}{sinkIntervalSec});
    $stripRate          = eval($rps->{driver}{stripRateFtPerSec})*12;    # in/sec
    if ($verbose>=3){pq($sinkInterval,$stripRate)}
    
    my $runControlPtr          = \%rSwingRunControl;
    my $loadedStateIsEmpty     = $loadedState->isempty;
    
    # Temp:
    my $segFluidMultRand    = 0;
    print "FIX segFluidMultRand\n";
    
    # Initialize dynamical variables:
    my $T0              = $rps->{integration}{t0};
    ($qs0,$qDots0)    = SetStartingConfig($segLens);
    #pq($qs0,$qDots0);
    
    my $tuckHtIn        = $rps->{configuration}{tuckHeightFt}*12;
    my $tuckVelInPerSec = $rps->{configuration}{tuckVelFtPerSec}*12;
    pq($tuckHtIn,$tuckVelInPerSec);

    if ($tuckHtIn or $tuckVelInPerSec){
        AdjustStartingForTuck($tuckHtIn,$tuckVelInPerSec,$segLens);
    }
    
    pq($qs0,$qDots0);

    $Dynams0 = $qs0->glue(0,$qDots0);  # Sic.  In my scheme, on initialization, the second half of dynams holds the velocities, not the momenta.
    pq($Dynams0);
    
    
    $dT = eval($rps->{integration}{plotDt});
    
    if ($verbose>=3){pq($T0,$Dynams0,$dT)}
    if ($verbose>=3){pqInfo($Dynams0)}
    
    SetSegStartTs($T0,$sinkInterval,$stripRate,$segLens,$shortStopInterval);
    
    $T      = $T0;  # Not a pdl yet.  Signals run needs initialization.
    #$Dynams = $Dynams0->copy;      ???
    
    $paramsStr    = GetLineStr()."\n".GetLeaderStr()."\n".GetTippetStr()."  ".GetFlyStr()."\n".
                    GetAmbientStr()."\n".GetStreamStr()."\n".$integrationStr;
    
    
    %opts_plot = (ZScale=>$rps->{integration}{plotZScale});
    
    #my $segVols     = $segLens*($pi/4)*$segCGDiams**2;
    #my $segBuoys    = $segVols*$waterOzPerIn3;
    #my $segDens     = $segWts/$segVols;
    #if ($verbose>=2){pq($segLens,$segCGDiams,$segVols,$segBuoys,$segWts,$segDens)}
    
    
    # Simply zero rod specific params here.
    Init_Hamilton(  "initialize",
                    $gravity,0,0,      # Standard gravity, No rod.
                    0,$numSegs,        # No rod.
                    $segLens,$segCGs,$segCGDiams,
                    $segWts,$segBuoys,$segKs,$segCs,
                    zeros(0),zeros(0),
                    $flyNomLen,$flyNomDiam,$flyWt,$flyBuoy,
                    $dragSpecsNormal,$dragSpecsAxial,
                    $segFluidMultRand,
                    $driverXSpline,$driverYSpline,$driverZSpline,
                    undef,undef,undef,
                    $frameRate,$driverStartTime,$driverEndTime,
                    undef,undef,
                    $T0,$Dynams0,$dT,
                    $runControlPtr,$loadedStateIsEmpty,
                    $profileStr,$bottomDepthFt,$surfaceVelFtPerSec,
                    $halfVelThicknessFt,$surfaceLayerThicknessIn,
                    $horizHalfWidthFt,$horizExponent,
                    $sinkInterval,$stripRate);
    
    return 1;
}



my (%opts_GSL,$t0_GSL,$t1_GSL,$dt_GSL,);
my $init_numSegs;
my $elapsedTime_GSL;
my ($finalT,$finalState);
my ($plotNumRodSegs,$plotErrMsg);
my ($plotTs,$plotXs,$plotYs,$plotZs);
my ($plotXLineTips,$plotYLineTips,$plotZLineTips);
my ($plotXLeaderTips,$plotYLeaderTips,$plotZLeaderTips);


my $stripping;
# These include the handle butt.


sub RSwingRun {
    
    ## Do the integration.  Either begin run or continue... Looks for a set return flag,  takes up where it left off (unless reset), and plots on return.  NOTE that the PAUSE button will only be reacted to during a call to DE, so in particular, while the solver is running.
    
    PrintSeparator("Doing the integration");
    
    if (!defined($T)){die "\$T must be set before call to RSwingRun\n"}
    
    
    my $JACfac;
    
    #if ($T->nelem == 1){
    if (ref($T) ne 'PDL'){
        
        $init_numSegs      = $numSegs;

        $elapsedTime_GSL    = 0;

        $t0_GSL             = Get_T0();

        $t1_GSL             = eval($rps->{integration}{t1});   # Requested end
        $dt_GSL             = $dT;
        my $lastStep_GSL       = int(($t1_GSL-$t0_GSL)/$dt_GSL);
        $t1_GSL             = $t0_GSL+$lastStep_GSL*$dt_GSL;    # End adjusted to keep the reported step intervals constant.

        $Dynams             = Get_DynamsCopy(); # This includes good initial $ps.
        if($verbose>=3){pq($t0_GSL,$t1_GSL,$dt_GSL,$Dynams)}
        
        $stripping          = ($segStartTs->isempty) ? 0 : 1;
        pq($segStartTs,$stripping);
        $iSegStart          = 0;
        
        $lineSegNomLens     = $segLens(-$init_numSegs:-1);
        
        my $h_init  = eval($rps->{integration}{dt0});
        %opts_GSL           = (type=>$rps->{integration}{stepperName},h_max=>1,h_init=>$h_init);
        if ($verbose>=3){pq(\%opts_GSL)}
            
        $T = pdl($T);   # To indicate that initialization has been done.  Prevents repeated initializations even if the user interrups during the first plot interval.

        if ($verbose>=2){print "Solver startup can be especially slow.  BE PATIENT.\n"}
        else {print "RUNNING SILENTLY, wait for return, or hit PAUSE to see the results thus far.\n"}
    }

    my $nextStart_GSL   = $T(-1)->sclr;
    
    if ($verbose>=3){
        $JACfac = JACget();
        pq($JACfac);
    }
    
    # Run the solver:
    my $timeStart = time();
    my $tStatus = 0;
    my $tErrMsg = '';;
    my ($interruptT,$interruptDynams);
    my $nextNumSegs;

    
    # Also, error scaling options. These all refer to the adaptive step size contoller which is well documented in the GSL manual.
    
    # epsabs and epsrel the allowable error levels (absolute and relative respectively) used in the system. Defaults are 1e-6 and 0.0 respectively.
    
    # a_y and a_dydt set the scaling factors for the function value and the function derivative respectively. While these may be used directly, these can be set using the shorthand ...
    
    # scaling, a shorthand for setting the above option. The available values may be y meaning {a_y = 1, a_dydt = 0} (which is the default), or yp meaning {a_y = 0, a_dydt = 1}. Note that setting the above scaling factors will override the corresponding field in this shorthand.
        
    ## See https://metacpan.org/pod/PerlGSL::DiffEq for the solver documentation.
    
    # I want the solver to return uniform steps of size $dt_GSL.  Thus, in the case of off-step returns (user or stripper interrupts) I need to make an additional one-step correction call to the solver, and edit its returns appropriately.  The correction step is always made with the new configuration and terminates on the next step.
    
    ## NextStart is always last report.  Also, each scheduled restart will be a last report.
    while ($nextStart_GSL < $t1_GSL) {
        
        my $thisStart_GSL = $nextStart_GSL;
        if ($verbose>=2){printf("\nt=%.2f   ",$thisStart_GSL)}
        
        my $thisStop_GSL;
        my $numSteps_GSL;
        my $nextSegStart_GSL;
        my $stopIsUniform;
        my $solution;
        
        if (!$stripping){   # Uniform starts and stops only.  On user interrup, starts at last reported time.
            $thisStop_GSL   = $t1_GSL;
            $numSteps_GSL   = int(($thisStop_GSL-$t0_GSL)/$dt_GSL);
            $stopIsUniform  = 1;
        }
        else {    # There are restarts.

            $nextSegStart_GSL    = $segStartTs($iSegStart)->sclr;
            if ( $thisStart_GSL > $nextSegStart_GSL) {
                die "ERROR:  Detected jumped event.\n";
            } elsif( $thisStart_GSL == $nextSegStart_GSL) {
                $nextSegStart_GSL    = $segStartTs(++$iSegStart)->sclr;
            }

            my $thisStep        = int(($thisStart_GSL-$t0_GSL)/$dt_GSL);
            my $lastUniformStop = $t0_GSL + $thisStep*$dt_GSL;
            my $startIsUniform  = ($thisStart_GSL == $lastUniformStop) ? 1 : 0;
 
            if ($startIsUniform) {

                my $boundedNextSegStart = ($nextSegStart_GSL > $t1_GSL) ? $t1_GSL : $nextSegStart_GSL;
                
                $numSteps_GSL       = int(($boundedNextSegStart-$thisStart_GSL)/$dt_GSL);
                if ($numSteps_GSL){     # Make whole steps to just before the next restart.
                    $thisStop_GSL   = $thisStart_GSL + $numSteps_GSL*$dt_GSL;
                    $stopIsUniform  = 1;
                } else {    # Need to make a single partial step to take us to the next restart or the end.
                    $thisStop_GSL   = $boundedNextSegStart;
                    $numSteps_GSL   = 1;
                    $stopIsUniform  = ($thisStop_GSL == $lastUniformStop+$dt_GSL) ? 1 : 0;
                }
            }
            else { # start is not uniform, so make no more than one step.
                
                $numSteps_GSL       = 1;
                
                my $nextUniformStop = $lastUniformStop + $dt_GSL;
                if ($nextSegStart_GSL < $nextUniformStop) {
                    $thisStop_GSL   = $nextSegStart_GSL;
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

        $solution = pdl(ode_solver([\&DEfunc_GSL,\&DEjac_GSL],[$thisStart_GSL,$thisStop_GSL,$numSteps_GSL],\%opts_GSL));
        
        if ($verbose>=3){print "\n SOLVER RETURN \n\n"}
        #pq($tStatus,$solution);
        
        # Check immediately for a user interrupt:
        $tStatus = DE_GetStatus();
        $tErrMsg = DE_GetErrMsg();
        
        # If the solver decides to give up, it prints "error, return value=-1", but does not return that -1.  Instead, it returns the last good solution, so in particular, the returned solution time will not equal $thisStop_GSL.
        if ($tStatus == 0 and $solution(0,-1) < $thisStop_GSL){
            $tStatus = -1;  # I'll help it.
            $tErrMsg    = "Solver Error";
        }
        
        if ($tStatus){
            $interruptT         = Get_TDynam();
            $interruptDynams    = Get_DynamsCopy();
            if (DEBUG and $verbose>=4){pq($tStatus,$tErrMsg,$interruptT,$interruptDynams)}
        }
        
        # If the solver returns the desired stop time, the step is asserted to be good, so keep the data.  Interrupts (set by the user, caught by TK, are only detected by DE() and passed to the solver.  So an iterrupt sent after the solver's last call to DE will be caught on the next solver call.
        
        # Always restart the while block (or the run call, if the stepper detected a user interrupt) with most recent good solver return.  That may not be on a uniform step if we were making up a partial step to a seg start:
        $nextStart_GSL  = $solution(0,-1)->sclr;    # Latest report time.
        my $theseDynams = $solution(1:-1,-1)->flat;
        
        my $nextDynams;
        
        my $beginningNewSeg = ($stripping and $nextStart_GSL == $nextSegStart_GSL) ? 1 : 0;

        #my $nextJACfac;
        if ($beginningNewSeg and $iSegStart >= 1){
            # Must reduce the number of segs.
            ($nextNumSegs,$nextDynams) = StripDynams($solution(:,-1)->flat);
            # $nextJACfac                 = StripDynams(JACget());
        } else {
            $nextNumSegs   = $theseDynams->nelem/6;
            $nextDynams     = $theseDynams;
           #$nextJACfac     = JACget();
        }
        if (DEBUG and $verbose>=4){pq($theseDynams,$nextStart_GSL,$nextDynams)}
 
         # There  is always at least one time (starting) in solution.  Never keep the starting data:
        my ($nRows,$nTimes) = $solution->dims;
        
        if ($nextStart_GSL == $thisStop_GSL) { # Got to the planned end of block run (so there are at least 2 rows.
            if (!$stopIsUniform) {  # The planned stop is not uniform.  Don't keep the stop data.  Note, however, that we will start the next solver run from here.
                $solution   = $solution(:,0:-2);
                $nTimes--;
            }
        }
        
        # In any case, we never keep the run start data:
        $solution   = ($nTimes == 1) ? zeros($nRows,0) : $solution(:,1:-1);
        #pq($solution);

        my ($ts,$paddedDynams) = PadSolution($solution,$init_numSegs);
        $T = $T->glue(0,$ts);
        $Dynams = $Dynams->glue(1,$paddedDynams);
        if (DEBUG and $verbose>=4){pq($T,$Dynams)}
        

        if ($verbose>=3){print "END_TIME=$nextStart_GSL\nEND_DYNAMS=$theseDynams\n\n"}
        #pq($T,$Dynams);
        
        if ($nextStart_GSL < $t1_GSL and $nextNumSegs and $tStatus >= 0) {
            # Either no error, or user interrupt.
            
            Init_Hamilton("restart_stripping",$nextStart_GSL,$nextNumSegs,$nextDynams,$beginningNewSeg);
        }

        if (!$tStatus and !$nextNumSegs){
            $tErrMsg = "Stripped all the line in.\n";
        }
        if ($tStatus or !$nextNumSegs){last}
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
    my $numISegs = $numSegs;
    ($plotXs,$plotYs,$plotZs) = map {zeros($numISegs,0)} (0..2);
    my $plotRs = zeros($numISegs-1,0);
    
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
                            Calc_Qs($tPlot,$tDynams,$lineTipOffset,$leaderTipOffset);

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
            
            my ($tt,$tDynams) = PadSolution($interruptSolution,$init_numSegs);
            
            my ($tXs,$tYs,$tZs,$tRs,$XLineTip,$YLineTip,$ZLineTip,$XLeaderTip,$YLeaderTip,$ZLeaderTip) =
                            Calc_Qs($tPlot,$tDynams,$lineTipOffset,$leaderTipOffset);
            if (DEBUG and $verbose>=4){pq($tXs,$tYs,$tZs)}
            
            
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
            
            if (DEBUG and $verbose>=4){
                    print "Appending interrupt data\n";
                    pq($tt,$tXs,$tYs,$tZs);
            }
        #        }
    }
    
    
    if (DEBUG and $verbose>=4){pq($plotTs,$plotXs,$plotYs,$plotZs,$plotRs)}
    if (DEBUG and $verbose>=4){pq($plotXLineTips,$plotYLineTips,$plotZLineTips,$plotXLeaderTips,$plotYLeaderTips,$plotZLeaderTips)}
    
    
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
    
    my $titleStr = "RSwing - " . $dateTimeLong;
    
    $plotNumRodSegs = 0;
    RCommonPlot3D('window',$rps->{file}{save},$titleStr,$paramsStr,
    $plotTs,$plotXs,$plotYs,$plotZs,$plotXLineTips,$plotYLineTips,$plotZLineTips,$plotXLeaderTips,$plotYLeaderTips,$plotZLeaderTips,$plotNumRodSegs,$plotErrMsg,$verbose,\%opts_plot);
    
    
    # If integration has completed, tell the caller:
    if ($tPlot>=$t1_GSL or $tStatus < 0 or !$nextNumSegs) {
        if ($tStatus < 0){print "\n";pq($tStatus,$tErrMsg)}
        if (!$nextNumSegs){print "\n$tErrMsg"}
        &{$rSwingRunControl{callerStop}}();
    }
    
}



sub UnpackSolution {
    my ($solution) = @_;

    my $numSegs    = ($solution->dim(0)-1)/6;
    my $ts          = $solution(0,:);

    my $dxs         = $solution(1:$numSegs,:);
    my $dys         = $solution($numSegs+1:2*$numSegs,:);
    my $dzs         = $solution(2*$numSegs+1:3*$numSegs,:);

    my $dxps      = $solution(3*$numSegs+1:4*$numSegs,:);
    my $dyps      = $solution(4*$numSegs+1:5*$numSegs:);
    my $dzps      = $solution(5*$numSegs+1:-1,:);
    
    return ($ts,$dxs,$dys,$dzs,$dxps,$dyps,$dzps);
}

sub PadSolution {
    my ($solution,$init_numSegs) = @_;
    
    ## Adjust for the varying number of nodes due to stripping.
    
    if ($solution->isempty){return (zeros(0),zeros(0))}
    #pq($solution);
    
    my $numSegs    = ($solution->dim(0)-1)/6;
    my $numRemoved  = $init_numSegs - $numSegs;
    
    my ($ts,$dxs,$dys,$dzs,$dxps,$dyps,$dzps) = UnpackSolution($solution);
    my $nTs = $ts->nelem;
    
    
    my $extras = zeros($numRemoved,$nTs);
    #pq($dxs,$dys,$dxps,$dyps,$extras);
    
    my $paddedDynams = $extras->glue(0,$dxs)->glue(0,$extras)->glue(0,$dys)->glue(0,$extras)->glue(0,$dzs)->
                        glue(0,$extras)->glue(0,$dxps)->glue(0,$extras)->glue(0,$dyps)->glue(0,$extras)->glue(0,$dzps);
    
    return ($ts->flat,$paddedDynams);
}



        
sub StripDynams {
    my ($solution) = @_;
    
    if ($solution->dim(1) != 1){die "ERROR:  StripSolution requires exactly one row.\n"}
    
    my ($ts,$dxs,$dys,$dzs,$dxps,$dyps,$dzps) = UnpackSolution($solution->flat);
    
    if ($dxs->nelem <= 1){
        return(0,zeros(0));
    }
    
    my $strippedDynams = $dxs(1:-1)->glue(0,$dys(1:-1))->glue(0,$dzs(1:-1))->
                            glue(0,$dxps(1:-1))->glue(0,$dyps(1:-1))->glue(0,$dzps(1:-1));
    
    my $numSegs = $strippedDynams->nelem/6;
    return ($numSegs,$strippedDynams->flat);
    
}

=for
sub StripJACfac {
    my ($inJACfac) = @_;
    
    my ($ts,$dxs,$dys,$dxps,$dyps) = UnpackSolution($inJACfac);
    my $outJACfac = $ts->glue(0,$dxs(1:-1))->glue(0,$dys(1:-1))->glue(0,$dxps(1:-1))->glue(0,$dyps(1:-1));

    return ($outJACfac);
}
=cut
        
sub UnpackQsFromDynams {
    my ($tDynams) = @_;
    
    if ($tDynams->dim(1) != 1){die "ERROR:  \$tDynams must be a vector.\n"}
    
    my $numSegs    = ($tDynams->dim(0))/6;
    my $dxs         = $tDynams(0:$numSegs-1);
    my $dys         = $tDynams($numSegs:2*$numSegs-1);
    my $dzs         = $tDynams(2*$numSegs:3*$numSegs-1);
    
    return ($dxs,$dys,$dzs);
}


sub Calc_Qs {
    my ($t,$tDynams,$lineTipOffset,$leaderTipOffset) = @_;

    my $nargin = @_;
    #pq($nargin);

    ## Return the cartesian coordinates Xs and Ys of all the rod and line NODES.  These are used for plotting and reporting.
    
    # A key benefit of an entirely relative scheme is that changes in the dynamical variables at a node only affect outboard nodes, and that changes in the thetas change nodal cartesian positions and velocities in the same way.
    
    # Except if we need to calculate fluid drag, this function is not used during the integration, just for reporting afterward.  It returns cartesian coordinates for ALL the nodes, including the driven handle node.  If includeButt is true, it prepends the butt coord.
    
    my ($driverX,$driverY,$driverZ) = Calc_Driver($t);
    
    #pq($driverX,$driverY,$driverZ);
    
    my ($dxs,$dys,$dzs) = UnpackQsFromDynams($tDynams);
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
    
    if (DEBUG and $verbose>=4){print "Calc_Qs:\n Xs=$Xs\n Ys=$Ys\n Zs=$Zs\n drs=$drs\n"}

    my ($XLineTip,$YLineTip,$ZLineTip,$XLeaderTip,$YLeaderTip,$ZLeaderTip);
    if ($nargin > 2){
        ($XLineTip,$YLineTip,$ZLineTip) =
            Calc_QOffset($t,$Xs,$Ys,$Zs,$drs,$lineTipOffset);
        #pq($XLineTip);pqInfo($XLineTip);
        #die;
    }
    if ($nargin > 3){
        ($XLeaderTip,$YLeaderTip,$ZLeaderTip)  =
            Calc_QOffset($t,$Xs,$Ys,$Zs,$drs,$leaderTipOffset);
    }
        
    if (DEBUG and $verbose>=5){pq($XLineTip,$YLineTip,$ZLineTip,$XLeaderTip,$YLeaderTip,$ZLeaderTip)}
    
    return ($Xs,$Ys,$Zs,$drs,$XLineTip,$YLineTip,$ZLineTip,$XLeaderTip,$YLeaderTip,$ZLeaderTip);
}


sub Calc_QOffset {
    my ($t,$Xs,$Ys,$Zs,$drs,$offset) = @_;

    ## For plotting line and leader tip locations. Expects padded data. Note that the fractional position in the segs should be based on nominal seg lengths, since these positions stretch and contract with the material.  This means, in particular, I need to know the time to (re)compute the nominal active strip seg length.
    
    #pq($t,$Xs,$Ys,$drs,$offset);

    my $tRemainingSegs  = ($drs != 0); # sic
    my $tSegNomLens     = $lineSegNomLens * $tRemainingSegs; # Deal with the padding.
    
    #pq($tRemainingSegs,$tSegNomLens);
    
    # Adjust the segment adjacent to the rod tip:
    my $iRemainingSegs   = which(!$tRemainingSegs);
    if (!$iRemainingSegs->isempty){
        my $iFirstSeg   = $iRemainingSegs(0);
        my $iSegStarts  = which($segStartTs <= $t);
        if (!$iSegStarts->isempty){
            my $iSegStart       = $iSegStarts(-1);
            my $thisSegStartT   = $segStartTs($iSegStart);
            $tSegNomLens($iFirstSeg)  .=
                $tSegNomLens($iFirstSeg) - ($t-$thisSegStartT)*$stripRate;
        }
    }
    
    my $revNodeOffsets  = cumusumover(pdl(0)->glue(0,$tSegNomLens(-1:0)));
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



# FUNCTIONS USED IN SETTING UP THE MODEL AND THE INTEGRATION ======================================

sub GetLineStr {
    
    my $str = "TotalActiveLength=$rps->{line}{activeLenFt}\n";
    $str .= "LINE: ID=$rps->{line}{identifier}; ";
    $str .= " NomWt,NomDiam,CoreDiam=($rps->{line}{nomWtGrsPerFt},$rps->{line}{nomDiameterIn},$rps->{line}{coreDiameterIn}); ";
    $str .= " Len==$lineLenFt; ";
    $str .= " Mods(elastic,damping)=($rps->{line}{coreElasticModulusPSI},$rps->{line}{dampingModulusPSI})";

    return $str;
}


sub GetLeaderStr {
    
    my $sinkStr = (defined($levelLeaderSink))?
                sprintf(" CALC\'D SINK=%.3f;",$levelLeaderSink):"";
    
    my $str = "LEADER: ID=$leaderStr;$sinkStr ";
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
    $str .= " NomDispVol=$flyNomDispVol;";
    
    return $str;
}



sub GetAmbientStr {
    
    my $str = "AMBIENT: Gravity=$rps->{ambient}{gravity}; ";
    $str .= "DragSpecsNormal=($rps->{ambient}{dragSpecsNormal}); ";
    $str .= "DragSpecsAxial=($rps->{ambient}{dragSpecsAxial})";
    
    return $str;
}

sub GetStreamStr {
    
    my $str .= "PROFILE: ID=$profileStr; ";
    $str .= "SurfaceVelocity=$rps->{stream}{surfaceVelFtPerSec}; ";
    $str .= "SurfaceLayerThickness=$rps->{stream}{surfaceLayerThicknessIn}; ";
    $str .= "BottomDepth=$rps->{stream}{bottomDepthFt}; ";
    $str .= "VertHalfThick=$rps->{stream}{halfVelThicknessFt}";
    $str .= "HorHalfThickn=$rps->{stream}{horizHalfWidthFt}";
    $str .= "HorExp=$rps->{stream}{horizExponent}";
    
    return $str;
}


sub ConvertToInOz { use constant V_XX => 0;
    my ( $flyLineNomWtGrPerFt,$flyLineLengthFt,$lineLengthFt,$lineCoreElasticModulusPSI,
            $flyWeightGr,$flyBuoyancyGr) = @_;

    my $flyLineNomWeight        = $flyLineNomWtGrPerFt / (12*437.5);
    my $flyLineLength           = $flyLineLengthFt * 12;
    my $lineLength              = $lineLengthFt * 12;
    my $lineCoreElasticModulus  = $lineCoreElasticModulusPSI * 16;
    my $flyWeight               = $flyWeightGr / 437;
    my $flyBuoyancy             = $flyWeightGr / 437;
    
    if ($verbose>=3){
        print("\nConverted to In-Oz units ---\nflyLineNomWeight=$flyLineNomWeight\nflyLineLength=$flyLineLength\nlineLength=$lineLength\nlineElasticModulus=lineCoreElasticModulus\nflyWeight=$flyWeight\nflyBuoyancy=$flyBuoyancy\n\n");
    }
 
    return ($flyLineNomWeight,$lineLength,$lineLength,$lineCoreElasticModulus,$flyWeight);
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

sub PlotDriverSplines {
    my ($numTs,$driverXSpline,$driverYSpline,$driverZSpline) = @_;
    
    my ($dataXs,$dataYs,$dataZs) = map {zeros($numTs)} (0..2);
    #pq($dataXs,$dataYs,$dataZs);
    
    my $dataTs = $timeXs(0)+sequence($numTs)*($timeXs(-1)-$timeXs(0))/($numTs-1);
    #pq($dataTs);

    for (my $ii=0;$ii<$numTs;$ii++) {

        my $tt = $dataTs($ii)->sclr;

        $dataXs($ii) .= $driverXSpline->evaluate($tt);
        $dataYs($ii) .= $driverYSpline->evaluate($tt);
        $dataZs($ii) .= $driverZSpline->evaluate($tt);
    
    }
    #pq($dataXs,$dataYs,$dataZs);
    
    Plot($dataTs,$dataXs,"X Splined",$dataTs,$dataYs,"Y Splined",$dataTs,$dataZs,"Z Splined","Splines as Functions of Time");
}



sub RSwingSave {
    my ($filename) = @_;

    my($basename, $dirs, $suffix) = fileparse($filename);
#pq($basename,$dirs$suffix);

    $filename = $dirs.$basename;
    if ($verbose>=2){print "Saving to file $filename\n"}

    my $titleStr = "RSwing - " . $dateTimeLong;

    $plotNumRodSegs = 0;
    if ($rps->{integration}{savePlot}){
        RCommonPlot3D('file',$dirs.$basename,$titleStr,$paramsStr,
                    $plotTs,$plotXs,$plotYs,$plotZs,$plotXLineTips,$plotYLineTips,$plotZLineTips,$plotXLeaderTips,$plotYLeaderTips,$plotZLeaderTips,$plotNumRodSegs,$plotErrMsg,$verbose,\%opts_plot);
    }

#pq($plotTs,$plotXs,$plotYs,$plotZs);
                   
    if ($rps->{integration}{saveData}){
        RCommonSave3D($dirs.$basename,$rSwingOutFileTag,$titleStr,$paramsStr,
        $plotTs,$plotXs,$plotYs,$plotZs,$plotXLineTips,$plotYLineTips,$plotZLineTips,$plotXLeaderTips,$plotYLeaderTips,$plotZLeaderTips,$plotNumRodSegs,$plotErrMsg,
        $finalT,$finalState,$segLens);
    }
}


sub RSwingPlotExtras {
    my ($filename) = @_;
    
    if ($rps->{driver}{plotSplines}){PlotDriverSpline('file',121,$filename.'_driver')}

    my ($plotLineVXs,$plotLineVYs,$plotLineVAs,$plotLineVNs,$plotLine_rDots) = Get_ExtraOutputs();
    
    if ($rps->{integration}{plotLineVXs}){PlotMat($plotLineVXs,1000,"Line Node VXs - $dateTimeLong",'ONLY'.$filename.'_vx')}
    if ($rps->{integration}{plotLineVYs}){PlotMat($plotLineVYs,1000,"Line Node VYs - $dateTimeLong",'ONLY'.$filename.'_vy')}

    if ($rps->{integration}{plotLineVAs}){PlotMat($plotLineVAs,1000,"Line Node VAs - $dateTimeLong",'ONLY'.$filename.'_va')}
    if ($rps->{integration}{plotLineVNs}){PlotMat($plotLineVNs,1000,"Line Node VNs - $dateTimeLong",'ONLY'.$filename.'_vn')}

    if ($rps->{integration}{plotLine_rDots}){PlotMat($plotLine_rDots,1000,"ONLYLine Node rDots - $dateTimeLong",'ONLY'.$filename.'_rDot')}
}


# Required package return value:
1;
