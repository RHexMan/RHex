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

#Documentation for the individual setup and run parameters may found in the Run Params section below, where the fields of runParams are defined and defaulted.


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

our $VERSION='0.01';

#use Exporter 'import';
#our @EXPORT = qw($rps DoSetup LoadLine LoadLeader LoadDriver DoRun DoSave);

use Carp;
use Time::HiRes qw (time alarm sleep);
use Switch;
use File::Basename;
use Math::Spline;
use Math::Round;
use Scalar::Util qw(looks_like_number);


use PDL;
    # Import main PDL module (see PDL.pm for equivalents).  In particular, imports PDL::Math, which redefines many POSIX math functions.  To get the original, call POSIX::aFunction.
use PDL::NiceSlice;
use PDL::AutoLoader;    # MATLAB-like autoloader.
PDL::no_clone_skip_warning;

use RUtils::DiffEq;
use RUtils::Print;
use RUtils::Plot;

use RCommon;
use RCommonLoad;
use RHamilton3D;
use RCommonPlot3D;


# Run params ==================================

$verbose = 1;   # See RHexCommon.

# Declare variables and set defaults  -----------------


my %runParams;
### !!!! NOTE that after changing this structure, you should delete the widget prefs file.
$rps = \%runParams;

# SPECIFIC DISCUSSION OF PARAMETERS, TYPICAL AND DEFAULT VALUES:

$rps->{file} = {
    rSwing    => "RSwing3D v1.0, 4/7/2019",   # The existence of this field is used for verification that input file is a sink settings file.  It's contents don't matter for this purpose.
    settings        => "SpecFiles_Preference/RHexSwing3D.prefs",
#    settings        => "RHexSwing3D.prefs",
    line            => "",
    leader          => "",
    driver          => "",
    save            => "",
        # If non-empty, there is something to plot.
};


$rps->{line} = {
    identifier              => "",
    activeLenFt             => 55,
        # Total desired length from rod tip to fly.
    nomWtGrsPerFt           => 6,
    # This is the nominal.  If you are reading from a file, must be an integer.
    estimatedSpGrav        => 0.8,
    # Only used if line read from a file and finds no diameters.
    nomDiamIn           	=> 0.060,
    coreDiamIn          	=> 0.020,
    # Make a guess.  Used in computing effective Hook's Law constant from nominal elastic modulus.
    coreElasticModulusPSI   => 2.1e5,        # 2.5e5 seems not bad, but the line hangs in a curve to start so ??
    # I measured the painted 4 wt line (tip 12'), and got corresponding to assumed line core diam of 0.02", EM = 1.52e5.
    # Try to measure this.  Ultimately, it is probably just the modulus of the core, with the coating not contributing that much.  0.2 for 4 wt line, 8' long is ok.  For 20' 7wt, more like 2.  This probably should scale with nominal line weight.   A tabulated value I found for Polyamides Nylon 66 is 1600 to 3800 MPa (230,000 to 550,000 psi.)
    dampingModulusPSI          => 1e3,
    # Cf rod damping modulus.  I don't really understand this, but numbers much different from 1 slow the integrator way down.  For the moment, since I don't know how to get the this number for the various leader and tippet materials, I am taking this value for those as well.
	dampOnExpansionOnly			=> 1,

};



$rps->{leader} = {
    identifier      => "",
    text            => "leader - level",
    lenFt           => 12,
    wtGrsPerFt      => 8,   # Grains/ft
    diamIn          => 0.025,   # Inches
    coreDiamIn      => 0.015,
	coreElasticModulusPSI   => 2.1e5,
	dampingModulusPSI		=> 1e3,
};

    
$rps->{tippet} = {
    lenFt			=> 2,
    text			=> "tippet - mono",
    diamIn			=> 0.011,     #  0.011 - diam in thousanths = "X" rating
};

$rps->{fly} = {
    wtGr            => 20,
    nomDiamIn       => 0.25,
    nomLenIn        => 0.25,
    nomDispVolIn3   => 0.001,  	# Displacement of the material volume, not fluff vol.
	segLenIn		=> 6,
};



$rps->{ambient} = {
    nominalG                 => 1,
        # Set to 1 to include effect of vertical gravity, 0 is no gravity, any value ok.
    dragSpecsNormal          => "24,-1,1",
    dragSpecsAxial           => "1,-1,0.01",
    # RE in [25,5K], Wolfram given very nearly constant 1.0., this per unit length.
    #    CDragAirAxial         => 0.010,   # 0.008(smooth)-0.011(rough) from OrcaFlex, but water, air?
};

$rps->{stream} = {
    bottomDepthFt           => 10,
    surfaceVelFtPerSec      => 3,
    surfaceLayerThicknessIn => 1,
    halfVelThicknessFt      => 1,
    profileText             => "profile - const",

    horizHalfWidthFt        => 10,
    horizExponent           => 2,
    
    
    showProfile             => 1,
};


$rps->{configuration} = {
    crossStreamAngleDeg     => 90,   # Measured from downstream.
    curvatureInvFt          => "1/100", # Plus is convex downstream, zero (or +/- inf) is straight.
    preStretchMult          => 1.001,    # For reasons I don't understand, a little pre-stretching of the line lets the solver (even a stiff one) get started much faster.
    tuckHeightFt            => 0,
    tuckVelFtPerSec         => 0,
};

$rps->{driver} = {
    laydownIntervalSec      => 0,

    sinkIntervalSec         => 20,
    stripRateFtPerSec       => 2,

    startCoordsFt           => "0,-30,0",
    endCoordsFt             => "10,-40,0",
    pivotCoordsFt           => "0,-40,0",
    trackCurvatureInvFt     => "1/15",	# Positive is convex away from the pivot.
    trackSkewness           => 0,   # Positive is more curved later.
    startTime               => 4,
    endTime                 => 20,
    velocitySkewness        => 0,   # Positive is faster later later.

	smoothingOrder			=> 8,
    showTrackPlot           => 1,
};


$rps->{integration} = {
    numSegs			=> 10,
    segExponent     => 0.75,
    # Bigger than 1 concentrates more line nodes near rod tip.
    t0              => 0,		# initial time
    t1              => 50,		# final time.  Typically, set this to be longer than the driven time.
    dt0             => 1e-6,	# initial time step - better too small, too large crashes.
    minDt           => 1e-9,   # abandon integration and return if seemingly stuck.
    plotDt          => 1,		# Set to 0 to plot all returned times.
    plotZScale      => 1.0,
    
    stepperName     => "msbdf_j",
    
    showLineVXs     => 0,
    plotLineVYs     => 0,
    plotLineVAs     => 0,
    plotLineVNs     => 0,
    plotLine_rDots  => 0,

    savePlot        => 1,
    saveData        => 1,

    debugVerboseName    => "debugVerbose - 4",
	switchOnSlowing		=> 1,
	reportVerboseName	=> "reportVerb - 3",
	verboseName			=> "verbose - 2",
};

$rps->{lineLevel} = {
	nomWtGrsPerFt			=> 6,
	estimatedSpGrav			=> 0.8,
	nomDiamIn				=> 0.060,
	coreDiamIn				=> 0.020,
	coreElasticModulusPSI	=> 2.1e5,
	dampingModulusPSI		=> 1e4,
};

$rps->{leaderLevel} = {
    text            		=> "leader - level",
    lenFt           		=> 12,
    wtGrsPerFt      		=> 8,
    diamIn          		=> 0.020,
    coreDiamIn      		=> 0.010,
	coreElasticModulusPSI	=> 2.1e5,
	dampingModulusPSI		=> 1e3,
};

$rps->{driverStore} = {
    endCoordsFt             => "10,-40,0",
    pivotCoordsFt           => "0,-40,0",
    trackCurvatureInvFt     => "1/15",
    trackSkewness           => 0,   # Positive is more curved later.
    velocitySkewness        => 0,   # Positive is faster later later.
	smoothingOrder			=> 0,
};

# Package internal global variables ---------------------
my ($dateTimeLong,$dateTimeShort,$runIdentifier);

#print Data::Dump::dump(\%runParams); print "\n";



# Package subroutines ------------------------------------------

$doSetup = \&DoSetup;
	# Set global pointer for use by RCommonInterface which needs to talk to either RCast3D or RSwing3D.

sub DoSetup {
    
    ## Except for the preference file, files are not loaded when selected, but rather, loaded when run is called.  This lets the load functions use parameter settings to modify the load -- what you see (in the widget) is what you get. This procedure allows the preference file to dominate.  Suggestions in the rod files should indicate details of that particular rod construction, which the user can bring over into the widget via the preferences file or direct setting, as desired.

    PrintSeparator("*** Setting up the solver run ***",0,$verbose>=2);
	
    $dateTimeLong = scalar(localtime);
    if ($verbose>=2){print "$dateTimeLong\n"}
    
    my($date,$time) = ShortDateTime;
    $dateTimeShort = sprintf("(%06d_%06d)",$date,$time);
    
    $runIdentifier = 'RUN'.$dateTimeShort;
    
    if (DEBUG and $verbose>=6){print Data::Dump::dump(\%runParams); print "\n"}
    
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
    my ($str,$sval,$val);
	
    $str = "activeLenFt"; $sval = $rps->{line}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val <= 0){$ok=0; print "ERROR: $str = $sval - active length must be positive.\n"}
    elsif($verbose>=1 and ($val < 10 or $val > 75)){print "WARNING: $str = $sval - Typical range is [10,75].\n"}
    my $activeLen = $val;
    
    $str = "nomWtGrsPerFt"; $sval = $rps->{line}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - line nominal weight must be non-negative.\n"}
    elsif($verbose>=1 and ($val > 15)){print "WARNING: $str = $sval - Typical range is [1,15].\n"}
	
    $str = "nomDiamIn"; $sval = $rps->{line}{$str}; $val = eval($sval);
    if ($sval ne "---"){
		if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - Must be non-negative.\n"}
    	elsif($verbose>=1 and ($val < 0.03 or $val > 0.09)){print "WARNING: $str = $sval - Typical range is [0.030,0.090].\n"}
	}
	
    $str = "coreDiamIn"; $sval = $rps->{line}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 0.01 or $val > 0.05)){print "WARNING: $str = $sval - Typical range is [0.01,0.05].\n"}
    
    $str = "coreElasticModulusPSI"; $sval = $rps->{line}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 1e5 or $val > 4e5)){print "WARNING: $str = $sval - Typical range is [1e5,4e5].\n"}
    
    $str = "dampingModulusPSI"; $sval = $rps->{line}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 1.5 or $val > 2.5)){print "WARNING: $str = $sval - Values much different from 1 slow the solver down a great deal, while those much above 10 lead to anomalies during stripping.\n"}
    
    $str = "lenFt"; $sval = $rps->{leader}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - leader length must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 5 or $val > 15)){print "WARNING: $str = $sval - Typical range is [5,15].\n"}
    
    $str = "wtGrsPerFt"; $sval = $rps->{leader}{$str}; $val = eval($sval);
    if ($sval ne "---"){
		if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - weights must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 5 or $val > 15)){print "WARNING: $str = $sval - Typical range is [7,18].\n"}
	}
    
    $str = "diamIn"; $sval = $rps->{leader}{$str}; $val = eval($sval);
    if ($sval ne "---"){
		if(!looks_like_number($val) or $val <= 0){$ok=0; print "ERROR: leader $str = $sval - diams must be positive.\n"}
    	elsif($verbose>=1 and ($val < 0.004 or $val > 0.020)){print "WARNING: leader $str = $sval - Typical range is [0.004,0.020].\n"}
	}
    
   $str = "coreDiamIn"; $sval = $rps->{leader}{$str}; $val = eval($sval);
    if ($sval ne "---"){
		if(!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - Must be non-negative.\n"}
   	 elsif($verbose>=1 and ($val < 0.01 or $val > 0.05)){print "WARNING: $str = $sval - Typical range is [0.01,0.05].\n"}
	}
    
    $str = "lenFt"; $sval = $rps->{tippet}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - lengths must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 2 or $val > 12)){print "WARNING: $str = $sval - Typical range is [2,12].\n"}
    
    $str = "diamIn"; $sval = $rps->{tippet}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - diams must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 0.004 or $val > 0.012)){print "WARNING: $str = $sval - Typical range is [0.004,0.012].\n"}
    
    
    $str = "wtGr"; $sval = $rps->{fly}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - Fly weight must be non-negative.\n"}
    elsif($verbose>=1 and ($val > 15)){print "WARNING: $str = $sval - Typical range is [0,15].\n"}
    
    $str = "nomDiamIn"; $sval = $rps->{fly}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - Fly nom diam must be non-negative.\n"}
    elsif($verbose>=1 and ($val > 0.25)){print "WARNING: $str = $sval - Typical range is [0.1,0.25].\n"}
    
    $str = "nomLenIn"; $sval = $rps->{fly}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - Fly nom length must be non-negative.\n"}
    elsif($verbose>=1 and ($val > 1)){print "WARNING: $str = $sval - Typical range is [0.25,1].\n"}
    
    $str = "nomDispVolIn3"; $sval = $rps->{fly}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - Fly nom volume must be non-negative.\n"}
    elsif($verbose>=1 and ($val > 0.02)){print "WARNING: $str = $sval - Typical range is [0,0.005].\n"}

    $str = "segLenIn"; $sval = $rps->{fly}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - Fly seg length must be non-negative.\n"}
    elsif($verbose>=1 and ($val > 6)){print "WARNING: $str = $sval - Typical range is [0,6].\n"}

    $str = "nominalG"; $sval = $rps->{ambient}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - Gravity must be must be non-negative.\n"}
    elsif($verbose>=1 and ($val != 1)){print "WARNING: $str = $sval - Typical value is 1.\n"}
    
    my ($tt,$a,$b,$c,$err);
    $str = "dragSpecsNormal";
    $tt = Str2Vect($rps->{ambient}{$str});
    if ($tt->nelem != 3) {
        $ok=0;
        print "ERROR: $str must be of the form MULT,POWER,MIN where the first two are greater than zero and the last is greater than or equal to zero.\n";
    } else {
        $a = sclr($tt(0)); $b = sclr($tt(1)); $c = sclr($tt(2));
        if ($verbose>=1 and ($a<23 or $a>25 or $b<-1.1 or $b>-0.9 or $c<0.8 or $c>1.2)){print "WARNING: $str = $a,$b,$c - Experimentally measured values are 24,-1,1.\n"}
    }
    
    $str = "dragSpecsAxial";
    $tt = Str2Vect($rps->{ambient}{$str});
    if ($tt->nelem != 3) {
        $ok=0;
        print "ERROR: $str must be of the form MULT,POWER,MIN where the first two are greater than zero and the last is greater than or equal to zero.\n";
    } else {
        $a = sclr($tt(0)); $b = sclr($tt(1)); $c = sclr($tt(2));
        if ($verbose>=1 and ($a<10 or $a>12 or $b<-0.78 or $b>-0.70 or $c<0.01 or $c>1)){print "WARNING: $str = $a,$b,$c - Experiments are unclear, try  1,-1,0.01.  The last value should be much less than the equivalent value in the normal spec.\n"}
    }
    
    $str = "sinkIntervalSec"; $sval = $rps->{driver}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - Sink interval must be must be non-negative.\n"}
    elsif($verbose>=1 and $val > 35){print "WARNING: $str = $sval - Typical range is [0,35].\n"}
	if ($val ne ''){$rps->{driver}{$str} = DecimalRound($val)}
	
    $str = "stripRateFtPerSec"; $sval = $rps->{driver}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - Strip rate must be must be non-negative.\n"}
    elsif($verbose>=1 and $val > 5){print "WARNING: $str = $sval - Typical range is [0,5].\n"}
    
    $str = "bottomDepthFt"; $sval = $rps->{stream}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val <= 0){$ok=0; print "ERROR: $str = $sval - Bottom depth must be must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 3 or $val > 15)){print "WARNING: $str = $sval - Typical range is [3,15].\n"}
    
    $str = "surfaceLayerThicknessIn"; $sval = $rps->{stream}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - Water surface layer thickness must be must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 0.1 or $val > 2)){print "WARNING: $str = $sval - Typical range is [0.1,2].\n"}
    
    $str = "surfaceVelFtPerSec"; $sval = $rps->{stream}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - Water surface velocity must be non-negative.\n"}
    elsif($verbose>=1 and ($val < 1 or $val > 7)){print "WARNING: $str = $sval - Typical range is [1,7].\n"}
    
    $str = "halfVelThicknessFt"; $sval = $rps->{stream}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val <= 0 or $val > $rps->{stream}{bottomDepthFt}/2){$ok=0; print "ERROR: $str = $sval - Half thickness must be positive, and no greater than half the water depth.\n"}
    elsif($verbose>=1 and ($val < 0.2 or $val > 3)){print "WARNING: $str = $sval - Typical range is [0.2,3].\n"}
    
    $str = "horizHalfWidthFt"; $sval = $rps->{stream}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val <= 0){$ok=0; print "ERROR: $str = $sval - Must be must be positive.\n"}
    elsif($verbose>=1 and ($val < 3 or $val > 20)){print "WARNING: $str = $sval - Typical range is [3,20].\n"}
    
    $str = "horizExponent"; $sval = $rps->{stream}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 2 and $val != 0){$ok=0; print "ERROR: $str = $sval - Must be must be either 0 or greater than or equal to 2.\n"}
    elsif($verbose>=1 and ($val < 2 or $val > 10)){print "WARNING: $str = $sval - Typical range is [2,10].\n"}
    

    
    $str = "crossStreamAngleDeg"; $val = eval($rps->{configuration}{$str});
    if (!looks_like_number($val) or $val <= -180 or $val >= 180){$ok=0; print "ERROR: $str = $sval - cross stream angle must be in the range (-180,180).\n"}
    elsif($verbose>=1 and ($val < -180 or $val > 180)){print "WARNING: $str = $sval - Typical range is (-180,180).\n"}
    
    $str = "curvatureInvFt"; $val = eval($rps->{configuration}{$str});
    if (abs($val) > 2/$rps->{line}{activeLenFt}){$ok=0; print "ERROR: $str = $sval - line initial curvature must be in the range (-2\/activeLen,2\/activeLen).\n"}
    
    $str = "preStretchMult"; $sval = $rps->{configuration}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 0.9){$ok=0; print "ERROR: $str = $sval - Must be no less than 0.9.\n"}
    elsif($verbose>=1 and ($val < 1 or $val > 1.1)){print "WARNING: $str = $sval - Typical range is [1,1.1].\n"}
    
    $str = "tuckHeightFt"; $sval = $rps->{configuration}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val > 10)){print "WARNING: $str = $sval - Typical range is [0,10].\n"}
    
    $str = "tuckVelFtPerSec"; $sval = $rps->{configuration}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val > 10)){print "WARNING: $str = $sval - Typical range is [0,10].\n"}
    
    
    $str = "laydownIntervalSec"; $sval = $rps->{driver}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val > 1)){print "WARNING: $str = $sval - Typical range is [0,1].\n"}
    
    $str = "startCoordsFt";
    my $ss = Str2Vect($rps->{driver}{$str});
    if ($ss->nelem != 3) {
        $ok=0;
        print "ERROR: $str must be of the form X,Y,Z.\n";
    } else {
        $a = $ss(0)->sclr; $b = $ss(1)->sclr; $c = $ss(2)->sclr;
        if ($verbose and (abs($a) > 15+$activeLen or abs($b)>15+$activeLen or abs($c)>15)){print "WARNING: $str = $a,$b,$c - Typical horizontal values are less than an arm plus rod length plus active line length, while typical vertical values are less than an arm plus rod length.\n"}
    }
	
    $str = "endCoordsFt"; $sval = $rps->{driver}{$str};
	my $ee;
	if ($sval ne "---"){
		$ee = Str2Vect($sval);
		if ($ee->nelem != 3) {
			$ok=0;
			print "ERROR: $str must be of the form X,Y,Z.\n";
		} else {
			$a = $ee(0)->sclr; $b = $ee(1)->sclr; $c = $ee(2)->sclr;
			if ($verbose and (abs($a) > 15+$activeLen or abs($b)>15+$activeLen or abs($c)>15)){print "WARNING: $str = $a,$b,$c - Typical horizontal values are less than an arm plus rod length plus active line length, while typical vertical values are less than an arm plus rod length.\n"}
		}
	}

    my $trackLen = sqrt(sum($ee-$ss)**2);
    if ($trackLen > 30){print "WARNING: Track start-end length = $trackLen.  Expected maximum is 2 times an arm length plus a rod length.\n"}

    $str = "pivotCoordsFt";	$sval = $rps->{driver}{$str};
	if ($sval ne "---"){
		my $ff = Str2Vect($sval);
		if ($ff->nelem != 3) {
			$ok=0;
			print "ERROR: $str must be of the form X,Y,Z.\n";
		} else {
			$a = $ff(0)->sclr; $b = $ff(1)->sclr; $c = $ff(2)->sclr;
			my $sLen = sqrt(sum($ss-$ff)**2);
			my $eLen = sqrt(sum($ee-$ff)**2);
			if ($verbose and ($sLen>15 or $eLen>15 or $c<0)){print "WARNING: $str = $a,$b,$c - Typically the distance between the pivot and the start ($sLen) and end ($eLen) of the rod tip track is less than the rod plus arm length.  The typical pivot Z is about 5 feet.\n"}
		}
	}

	if (defined($ee)){
		my $tLen = sqrt(sum(($ee-$ss)**2));
		$str = "trackCurvatureInvFt"; $val = eval($rps->{driver}{$str});
		if ($sval ne "---"){
			if (!looks_like_number($val) or abs($val) > 2/$tLen){$ok=0; print "ERROR: $str = $sval - track curvature must be in the range (-2\/trackLen,2\/trackLen).  Positive curvature is away from the pivot.\n"}
		}
	}
    
    $str = "trackSkewness"; $sval = $rps->{driver}{$str}; $val = eval($sval);
	if ($sval ne "---"){
		if (!looks_like_number($val)){$ok=0; print "ERROR: $str = $sval - Must be a numerical value.\n"}
		elsif($verbose>=1 and ($val < -0.25 or $val > 0.25)){print "WARNING: $str = $sval - Positive values peak later.  Typical range is [-0.25,0.25].\n"}
	}

	if ($rps->{driver}{startTime} eq '' or $rps->{driver}{endTime} eq ''){$ok=0; print "ERROR: Start and end times must be numerical values.\n"}

    if ($rps->{driver}{startTime} >= $rps->{driver}{endTime}){
		print "WARNING:  motion start time greater or equal to motion end time means no rod tip motion will happen.  Resetting end time to equal start time.\n";
		$rps->{driver}{endTime} = $rps->{driver}{startTime};
	}
    
    $str = "velocitySkewness"; $sval = $rps->{driver}{$str}; $val = eval($sval);
	if ($sval ne "---"){
		if (!looks_like_number($val)){$ok=0; print "ERROR: $str = $sval - Must be a numerical value.\n"}
		elsif($verbose>=1 and ($val < -0.25 or $val > 0.25)){print "WARNING: $str = $sval - Positive values peak later.  Typical range is [-0.25,0.25].\n"}
	}
 
    $str = "smoothingOrder"; $sval = $rps->{driver}{$str}; $val = eval($sval);
	if ($sval ne "---"){
		if (!looks_like_number($val) or $val<0 or $val != POSIX::floor($val)){$ok=0; print "ERROR: $str = $sval - Must be a non-negative integer.\n"}
		elsif($verbose>=1 and ($val < -1 or $val > 1)){print "WARNING: $str = $sval - Zero disables smoothing, higher numbers give closer approximations.\n"}
	}

    $str = "numSegs"; $sval = $rps->{integration}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 1 or ceil($val) != $val){$ok=0; print "ERROR: $str = $sval - Must be an integer >= 1.\n"}
    elsif($verbose>=1 and ($val > 20)){print "WARNING: $str = $sval - Typical range is [5,20].\n"}
    
    $str = "segExponent"; $sval = $rps->{integration}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val <= 0){$ok=0; print "ERROR: $str = $sval - Seg exponent must be positive.\n"}
    elsif($verbose>=1 and ($val < 0.5 or $val > 2)){print "WARNING: $str = $sval - Typical range is [0.5,2].\n"}
    
    $str = "t0"; $sval = $rps->{integration}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 0){$ok=0; print "ERROR: $str = $sval - Must be non-negative.\n"}
    elsif($verbose>=1 and ($val != 0)){print "WARNING: $str = $sval - Usually 0.\n"}
	if ($val ne ''){$rps->{integration}{$str} = DecimalRound($val)}
	my $t0 = $val;
	
    $str = "t1"; $sval = $rps->{integration}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val <= $rps->{integration}{t0}){$ok=0; print "ERROR: $str = $sval - Must larger than t0.\n"}
    elsif($verbose>=1 and ($val > 60)){print "WARNING: $str = $sval - Usually less than 60.\n"}
 	if ($val ne ''){$rps->{integration}{$str} = DecimalRound($val)}
	
    $str = "dt0"; $sval = $rps->{integration}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val <= 0){$ok=0; print "ERROR: $str = $sval - Must be positive.\n"}
    elsif($verbose>=1 and ($val > 1e-4 or $val < 1e-7)){print "WARNING: $str = $sval - Typical range is [1e-4,1e-7].\n"}
   
    $str = "plotDt"; $val = eval($rps->{integration}{$str});
    if (!looks_like_number($val) or $val <= 0){$ok=0; print "ERROR: $str = $sval - Must be positive.\n"}
    elsif($verbose>=1 and ($val < 0.1 or $val > 1)){print "WARNING: $str = $sval - Typical range is [0.1,1].\n"}
	if ($val ne ''){$rps->{integration}{$str} = DecimalRound($val)}
	
    $str = "plotZScale"; $sval = $rps->{integration}{$str}; $val = eval($sval);
    if (!looks_like_number($val) or $val < 1){$ok=0; print "ERROR: $str = $sval - Magnification must be no less than 1.\n"}
    elsif($verbose>=1 and ($val > 5)){print "WARNING: $str = $sval - Typical range is [1/5].\n"}
    
	
    return $ok;
}

my $loadedState = zeros(0); # Disable for now.  Continuing a previously saved run, see RHexCastPkg.

my ($loadedLineSegLens,$loadedT0);


my ($driverIdentifier);
my $integrationStr;

my ($driverStartTime,$driverEndTime);
my ($driverTs,$driverXs,$driverYs,$driverZs);  # pdls.

my $driverFieldsDisableInds;

sub SwapDriverFields {
    my ($fromStorage) = @_;

	if ($fromStorage){

		$rps->{driver}{endCoordsFt}			= $rps->{driverStore}{endCoordsFt};
		$rps->{driver}{pivotCoordsFt}		= $rps->{driverStore}{pivotCoordsFt};
		$rps->{driver}{trackCurvatureInvFt}	= $rps->{driverStore}{trackCurvatureInvFt};
		$rps->{driver}{trackSkewness}		= $rps->{driverStore}{trackSkewness};
		$rps->{driver}{velocitySkewness}	= $rps->{driverStore}{velocitySkewness};
		$rps->{driver}{smoothingOrder}		= $rps->{driverStore}{smoothingOrder};
		
		#print "Swapping from storage...\n panel fields: ($rps->{driver}{endCoordsFt}),($rps->{driver}{pivotCoordsFt}),$rps->{driver}{trackCurvatureInvFt},$rps->{driver}{trackSkewness},$rps->{driver}{velocitySkewness},$rps->{driver}{smoothingOrder}.\n\n";

	} else {  # to storage
	
		# Just swap the enabled values.
		my $enabled = ones(6);
		$enabled($driverFieldsDisableInds) .= 0;
		
		if($enabled(0)){$rps->{driverStore}{endCoordsFt}
											= $rps->{driver}{endCoordsFt} }
		if($enabled(1)){$rps->{driverStore}{pivotCoordsFt}
											= $rps->{driver}{pivotCoordsFt} }
		if($enabled(2)){$rps->{driverStore}{trackCurvatureInvFt}
											= $rps->{driver}{trackCurvatureInvFt} }
		if($enabled(3)){$rps->{driverStore}{trackSkewness}
											= $rps->{driver}{trackSkewness} }
		if($enabled(4)){$rps->{driverStore}{velocitySkewness}
											= $rps->{driver}{velocitySkewness} }
		if($enabled(5)){$rps->{driverStore}{smoothingOrder}
											= $rps->{driver}{smoothingOrder} }
		#print "Swapping to storage...\n \$enabled = $enabled\n storage fields: ($rps->{driverStore}{endCoordsFt}),($rps->{driverStore}{pivotCoordsFt}),$rps->{driverStore}{trackCurvatureInvFt},$rps->{driverStore}{trackSkewness},$rps->{driverStore}{velocitySkewness},$rps->{driver}{smoothingOrder}.\n\n";

	}
}


$loadDriver = \&LoadDriver;	# Set global pointer for use by RCommonInterface.

sub LoadDriver {
    my ($driverFile,$updatingPanel,$initialize) = @_;
	
	## Works in feet.  Final conversion to cgs happens in SetupDriver();
    
    ## Process castFile if defined, otherwise set directly from cast params --------
    
    # Unset cast pdls (to empty rather than undef):
    ($driverXs,$driverYs,$driverZs,$driverTs) = map {zeros(0)} (0..3);
	
    # The cast drawing is expected to be in SVG.  See http://www.w3.org/TR/SVG/ for the full protocol.  SVG does 2-DIMENSIONAL drawing only! See the function SVG_matrix() below for the details.  Ditto resplines.
    
	my $stdPrint = (!$updatingPanel and $verbose>=2) ? 1 : 0;

    if ($stdPrint){PrintSeparator("Loading rod tip motion")}
    #if(1){PrintSeparator("Loading rod tip motion")}
	
	$driverStartTime    = $rps->{driver}{startTime};
    $driverEndTime      = $rps->{driver}{endTime};
    if ($stdPrint){pq($driverStartTime,$driverEndTime)}
	
	my $ok = 1;
    
    if ($driverFile) {
        
        if ($verbose>=2){print "Data from $driverFile.\n"}
        
		my $inData;
        open INFILE, "< $driverFile" or $ok = 0;
        if (!$ok){print "ERROR: $!\n";return 0}
		{
			local $/;
        	$inData = <INFILE>;
		}
        close INFILE;
		
		# Always swap the currently enabled fields to level storage.  This keeps the storage up to date:
		if ($updatingPanel){
			# Do this early, so subsequent disables print subsequently;

			if (!$initialize){

				SwapDriverFields(0); # Swap out only enabled fields.
				SwapDriverFields(1);
			} # else, just use the fields that were loaded.

			
			$rps->{driver}{endCoordsFt}			= "---";
			$rps->{driver}{pivotCoordsFt}		= "---";
			$rps->{driver}{trackCurvatureInvFt}	= "---";
			$rps->{driver}{trackSkewness}		= "---";
			
			$driverFieldsDisableInds	= sequence(4);
			@driverFieldsDisable		= @main::driverFields[0..3];
				# When reading from a file, leave velocitySkewness and smoothing enabled.
			
			return 1;
		}
		
        my ($name,$dir,$ext) = fileparse($driverFile,'\..*');
        $driverIdentifier = $name;
        if ($verbose>=4){pq($driverIdentifier)}
        
        if ($ext eq ".txt"){
            if (!SetDriverFromTXT($inData)){$ok=0;goto BAD_RETURN};
        } else {  print "ERROR: Rod tip motion file must have .txt extension"; return 0}
		
		
		# Deal with the no motion case when the start time is greater or equal to the end time.  If we've gotten here, there is at least one good rod tip location:
		if ($driverStartTime >= $driverEndTime){
			$driverXs = $driverXs(0)*ones(2);
			$driverYs = $driverYs(0)*ones(2);
			$driverZs = $driverZs(0)*ones(2);
			
			$driverTs = $driverStartTime + sequence(2);
		}
		

    } else {
	
		if ($updatingPanel){

			print "Motion set from params\n";

			if (!$initialize){

				SwapDriverFields(0); # Swap out only enabled fields.
				SwapDriverFields(1); # Swap all fields back.
			} # else initializing.  Use what you got, don't swap anything
			
			$rps->{driver}{smoothingOrder}	= "---";

			$driverFieldsDisableInds		= pdl(5);
			@driverFieldsDisable			= $main::driverFields[5];
			
			return 1;
		}
	
        if ($verbose>=2){print "No file.  Setting rod tip motion from params.\n"}
        SetDriverFromParams();
        $driverIdentifier = "Parameterized";
    }
	
BAD_RETURN:
    if (!$ok){print "LoadDriver DETECTED ERRORS.\n"}
    
    return $ok;
}


my $numDriverTimes = 21;
my $driverSmoothingFraction = 0.2;

sub SetDriverFromParams {
    
    ## If driver was not already read from a file, construct a normalized one on a linear base here from the widget's track params:
	
	## Still working in feet.
    my $startCoords = Str2Vect($rps->{driver}{startCoordsFt});
    my $endCoords   = Str2Vect($rps->{driver}{endCoordsFt});
    my $pivotCoords = Str2Vect($rps->{driver}{pivotCoordsFt});
    
    my $curvature   = eval($rps->{driver}{trackCurvatureInvFt});
        # 1/Inches.  Positive curvature is away from the pivot.
    my $length      = sqrt(sum(($endCoords - $startCoords)**2));
    
    if ($length == 0 or $driverStartTime >= $driverEndTime){  # No rod tip motion
		# KLUGE:  Spline interpolation requires at least 2 distinct time values.  The fact that the second time value is greater than the drive end time will not break the implementation of Calc_Driver() in Hamilton.
		
        ($driverXs,$driverYs,$driverZs)	=
				map {ones(2)*$startCoords($_)} (0..2);
		
        $driverTs	= $driverStartTime + sequence(2);
		pq($driverXs,$driverYs,$driverZs,$driverTs);

        return;
    }
	
    my $totalTime = $driverEndTime-$driverStartTime;
    $driverTs = $driverStartTime +
					sequence($numDriverTimes)*$totalTime/($numDriverTimes-1);
    
    my $tFracts     = sequence($numDriverTimes+1)/($numDriverTimes);
    my $tMultStart  = 1-SmoothChar($tFracts,0,$driverSmoothingFraction);
    my $tMultStop   = SmoothChar($tFracts,1-$driverSmoothingFraction,1);
    
    my $slopes  = $tMultStart*$tMultStop;
    my $vals    = cumusumover($slopes(0:-2));
    $vals   /= $vals(-1);
    
    my $coords = $startCoords + $vals->transpose*($endCoords-$startCoords);
    
    #my $plotCoords = $driverTs->transpose->glue(0,$coords);
    #PlotMat($plotCoords);
    
    if ($length and $curvature){
        #pq($coords);
        # Get vector in the plane of the track ends and the pivot that is perpendicular to the track and pointing away from the pivot.  Do this by projecting the pivot-to-track start vector onto the track, and subtracting that from the original vector:
        my $refVect     = $startCoords - $pivotCoords;
        my $unitTrack   = $endCoords - $startCoords;
        $unitTrack      /= sqrt(sum($unitTrack**2));
		
        my $unitDisplacement    = $refVect - sum($refVect*$unitTrack)*$unitTrack;
        $unitDisplacement      /= sqrt(sum($unitDisplacement**2));
        #pq($length,$curvature,$refVect,$unitTrack,$unitDisplacement);
        
        my $xs  = sqrt(sumover(($coords-$startCoords)**2));   # Turned into a flat vector.
        
        my $skewExponent = $rps->{driver}{trackSkewness};
        if ($skewExponent){
            $xs = SkewSequence(0,$length,$skewExponent,$xs);
        }
        
        my $secantOffsets = SecantOffsets(1/$curvature,$length,$xs);     # Returns a flat vector.
		
        $coords += $secantOffsets->transpose x $unitDisplacement;
    }

    
    ($driverXs,$driverYs,$driverZs)   = map {$coords($_,:)->flat} (0..2);
    #pq($coords);
    
    my $velExponent = $rps->{driver}{velocitySkewness};
    if ($velExponent){
        #pq($driverTs);
        $driverTs = SkewSequence($driverStartTime,$driverEndTime,-$velExponent,$driverTs);
        # Want positive to mean fast later.
    }
    
	#pq($driverTs,$driverXs,$driverYs,$driverZs);
	
    if (DEBUG and $rps->{driver}{showTrackPlot}){
        my %opts = (gnuplot=>$gnuplot,xlabel=>"x-axis (ft)",ylabel=>"y-axis (ft)",zlabel=>"z-axis (ft)",ZScale=>$rps->{integration}{plotZScale});
		
        Plot3D($driverXs,$driverYs,$driverZs,"Rod Tip Track",\%opts);
    }
}


sub SetDriverFromTXT {
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
    	my $startCoords = Str2Vect($rps->{driver}{startCoordsFt});
		$driverXs += $startCoords(0);
		$driverYs += $startCoords(1);
		$driverZs += $startCoords(2);
	}
	
	$driverTs = $driverStartTime + $tOffsets*($driverEndTime-$driverStartTime);
	
 	my $smoothingOrder = $rps->{driver}{smoothingOrder};
	if ($smoothingOrder){
		#my %opts = (gnuplot=>$gnuplot,persist=>"persist");
		my %opts = (gnuplot=>$gnuplot);
		my $plotOpts = ($rps->{driver}{showTrackPlot}) ? \%opts : 0;
		my $numTimes	= $driverTs->nelem;
		if (2*$smoothingOrder+1 > $numTimes/2){print "Error: 2*smoothingOrder+1 must be no greater than the number of loaded timesteps divided by 2.\n"; return 0}

		my $smoothEnds	= ($numTimes >= 10) ? 5 : POSIX::floor($numTimes/2);
			# Always smooth ends as well.
		SmoothDriver($smoothingOrder,$smoothEnds,$plotOpts,
						$driverTs,$driverXs,$driverYs,$driverZs);
	}

	
    if ($verbose>=3){pq($driverStartTime,$driverEndTime,$driverXs,$driverYs,$driverZs,$driverTs)}
	
    if (DEBUG and $rps->{driver}{showTrackPlot}){
	
        my %opts = (gnuplot=>$gnuplot,xlabel=>"x-axis (ft)",ylabel=>"y-axis (ft)",zlabel=>"z-axis (ft)",ZScale=>$rps->{integration}{plotZScale});

        Plot3D($driverXs,$driverYs,$driverZs,"Rod Tip Track",\%opts);
    }
    
    return $ok;
}


my $numSegs;
my ($segMasses,$segLens,$segDiams,$segVols,$segKs,$segCs);
my ($segCGElasticDiamsIn,$segCGElasticModsPSI,$segCGDampingDiamsIn,$segCGDampingModsPSI);
my ($flyMass,$flyBuoy,$flyNomLen,$flyNomDiam,$flyNomDispVol);
my ($lineLenFt,$lineTipOffset,$leaderTipOffset);
my ($activeLen);


sub SetupModel {
    
    ## Called just prior to running. Convert the line file data to a specific model for use by the solver.
    
    PrintSeparator("Setting up model");
    
    if ($loadedState->isempty){
        
        $numSegs		= $rps->{integration}{numSegs};
        $segLens		= zeros(0);
        # Nominal because we will later deal with stretch.
        
    } else{
        
        die "Not yet implemented.\nStopped";
        $numSegs               			= $loadedLineSegLens->nelem;
        $rps->{integration}{numSegs}	= $numSegs;   # Show the user.
        $segLens						= $loadedLineSegLens;
    }
    
    
    # Work first with the true segs.  Will deal with the fly pseudo-segment later.
	
    my $activeLenFt = $rps->{line}{activeLenFt};
	
    $lineLenFt = $activeLenFt - $leaderLenFt - $tippetLenFt;
    
	# These next used in Run(), so ok to convert:
    $leaderTipOffset    = $tippetLenFt*$feetToCms;
    $lineTipOffset      = $leaderTipOffset + $leaderLenFt*$feetToCms;
	#pq($lineTipOffset,$leaderTipOffset);

	my $flySegLenFt	= $rps->{fly}{segLenIn}/12;
	if ($verbose>=3){pq($flySegLenFt)}
	my $tNumSegs	= ($flySegLenFt)?$numSegs-1:$numSegs;
	
    my $fractNodeLocs;
    if ($segLens->isempty) {
        $fractNodeLocs = sequence($tNumSegs+1)**$rps->{integration}{segExponent};
		#pq($fractNodeLocs);
    } else {
        $fractNodeLocs = cumusumover(zeros(1)->glue(0,$segLens));
    }
	#pq($fractNodeLocs);
    $fractNodeLocs /= $fractNodeLocs(-1);
	
	if ($flySegLenFt){
		my $flyFract = $flySegLenFt/$activeLenFt;
		# Rescale the exponential nodes to allow for the fly eye node:
		$fractNodeLocs *= 1-$flyFract;
		$fractNodeLocs = $fractNodeLocs->glue(0,pdl(1));
	}
    if (DEBUG and $verbose>=3){pq($fractNodeLocs)}

    my $nodeLocs    = $activeLenFt*$fractNodeLocs;
    if ($verbose>=3){pq($nodeLocs)};

    # Figure the seg lengths.
    $segLens	= $nodeLocs(1:-1)-$nodeLocs(0:-2);
    if ($verbose>=3){pq($segLens)}
	
    # Figure the segment weights -------

    # Take just the active part of the line, leader, tippet.  Low index is TIP:
    my $lastFt  = POSIX::ceil($activeLenFt);
    #pq ($lastFt,$loadedGrsPerFt);
    
    my $availFt = $loadedGrsPerFt->nelem;
    if ($lastFt >= $availFt){confess "\nERROR:  Active length (sum of line outside rod tip, leader, and tippet) requires more fly line than is available in file.  Set shorter active len or load a different line file.\nStopped"}
    
    my $activeLineGrs   =  $loadedGrsPerFt($lastFt-1:0)->copy;    # Re-index to start at rod tip.
    if (DEBUG and $verbose>=4){pq($activeLineGrs)}
	
	my $segGrs = SegShares($activeLineGrs,$nodeLocs);
	
	$segMasses = $segGrs*$grainsToGms;
	if ($verbose>=3){pq($segGrs,$segMasses)}

	my $totalLineLoopWtOz = sum($segMasses)/$ouncesToGms;
	
	my $activeLineVolsPerFt   =  $loadedVolsPerFt($lastFt-1:0)->copy;    # Re-index to start at rod tip.
    if (DEBUG and $verbose>=4){pq($activeLineVolsPerFt)}
	
	my $segVolsIn3 = SegShares($activeLineVolsPerFt,$nodeLocs);
    $segVols = $segVolsIn3 * $inchesToCms**3;
	pq($segVols);
	if (DEBUG and $verbose>=4){pq($segVols)}
	
    my $activeDiamsIn   =  $loadedDiamsIn($lastFt-1:0)->copy;
		# Re-index to start at rod tip.
    if (DEBUG and $verbose>=4){pq($activeDiamsIn)}

    #my $fractCGs        = (1-$segCGs)*$fractNodeLocs(0:-2)+$segCGs*$fractNodeLocs(1:-1);
    #if (DEBUG and $verbose>=4){pq($activeDiamsIn,$fractCGs)}
    
	# Having extracted $fractCGs, we are now free to convert segLens:
	$segLens	*= $feetToCms;
	pq($segLens);
		
    #$segCGDiams         = ResampleVectLin($activeDiamsIn,$fractCGs);
    $segDiams	= ResampleVectLin($activeDiamsIn,$fractNodeLocs(1:-1)) * $inchesToCms;	# Our convention is diameter at outboard node, where the mass is nominally concentrated.
        # For the line I will compute Ks and Cs based on the diams at the segCGs.
    if ($verbose>=3){pq($segDiams)}
    
    my $activeElasticDiamsIn =  $loadedElasticDiamsIn($lastFt-1:0)->copy;
    my $activeElasticModsPSI =  $loadedElasticModsPSI($lastFt-1:0)->copy;
    my $activeDampingDiamsIn =  $loadedDampingDiamsIn($lastFt-1:0)->copy;
    my $activeDampingModsPSI =  $loadedDampingModsPSI($lastFt-1:0)->copy;

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
	$segKs = $nodeElasticMods*$nodeElasticAreas/$segLens; # dynes to stretch 1 cm. ??
	# Basic Hook's law, on just the level core, which contributes most of the stretch resistance.
	
	my $nodeDampingAreas    = ($pi/4)*$nodeDampingDiams**2;
	$segCs = $nodeDampingMods*$nodeDampingAreas/$segLens; # Dynes to stretch 1 cm.
	# By analogy with Hook's law, on the whole diameter. Figure the elongation damping coefficients USING FULL LINE DIAMETER since the plastic coating probably contributes significantly to the stretching friction.
	
	if ($verbose>=3){pq($segKs,$segCs)}
	
    # Set the fly specs -------------
    $flyMass		= eval($rps->{fly}{wtGr}) * $grainsToGms;
    $flyNomLen      = eval($rps->{fly}{nomLenIn}) * $inchesToCms;
    $flyNomDiam     = eval($rps->{fly}{nomDiamIn}) * $inchesToCms;
	$flyNomDispVol  = eval($rps->{fly}{nomDispVolIn3}) * $inchesToCms**3;
    if ($verbose>=2){pq($flyMass,$flyNomLen,$flyNomDiam,$flyNomDispVol)}
    
    # Combine rod and line (including leader and tippet), but not fly:
    $segMasses	= $segMasses->glue(0,pdl(0));
		# Fly mass will be added in Hamilton.
	$segMasses	= 0.5*($segMasses(0:-2)+$segMasses(1:-1));
		# We will treat the mass as if it is located at the outboard node of the segment and has the average value of the preceeding and following segs.
	
	# Do the same for the volumes:
    $segVols	= $segVols->glue(0,pdl(0));
		# Fly displacement vol will be added in Hamilton.
	$segVols	= 0.5*($segVols(0:-2)+$segVols(1:-1));
		# We will treat the vol as if it is located at the outboard node of the segment and has the average value of the preceeding and following segs.
	
    my $activeWtOz = (sum($segMasses)+pdl($flyMass))/$ouncesToGms;
    if ($verbose>=2){print "\n";pq($activeWtOz);print "\n"}
}


my ($driverXSpline,$driverYSpline,$driverZSpline);


sub SetupDriver {
    
    ## Prepare the external constraint at the rod tip.  Applied during integration by Calc_Driver().
    
    PrintSeparator("Setting up rod tip driver");
    
    # Set up spline interpolations, so that during integration we can just eval.
	
    # Interpolate in arrays, all I have for now:
	#pq($driverTs,$driverXs,$driverYs,$driverZs);
	
    my @aDriverTs	= list($driverTs);
    my @aDriverXs   = list($driverXs * $feetToCms);
    my @aDriverYs   = list($driverYs * $feetToCms);
    my @aDriverZs   = list($driverZs * $feetToCms);
	
	#pq(\@aDriverTs,\@aDriverXs,\@aDriverYs,\@aDriverZs);
    
    $driverXSpline = Math::Spline->new(\@aDriverTs,\@aDriverXs);
    $driverYSpline = Math::Spline->new(\@aDriverTs,\@aDriverYs);
    $driverZSpline = Math::Spline->new(\@aDriverTs,\@aDriverZs);
    
    # Plot the driver with enough points in each segment to show the spline behavior:
    #    if ($rps->{driver}{plotSplines}){

	if ($rps->{driver}{showTrackPlot}){
        my $numTs = 30;	# 30 is good.  Not so many that we can't see the velocity differences.
        PlotDriverSplines($numTs,$driverTs(0),$driverTs(-1),$driverXSpline,$driverYSpline,$driverZSpline,1);  # Plot 3D.
    }
	
    if (DEBUG and $rps->{driver}{showTrackPlot} and $verbose>=3){
        PlotDriverSplines(101,$driverXSpline,$driverYSpline,$driverZSpline);
    }
    
    # Set driver string:
    my $tTT = sprintf("%.3f",$driverStartTime-$driverEndTime);
	
    $integrationStr = "DRIVER: ID=$driverIdentifier;  INTEGRATION: t=($rps->{integration}{t0}:$rps->{integration}{t1}:$rps->{integration}{plotDt}); $rps->{integration}{stepperName}; t=(0,$tTT)";
    
    if (DEBUG and $verbose>=4){pq $integrationStr}
}



my ($segStartTs,$iSegStart);

sub SetSubsequentSegStartTs {
    my ($t0,$sinkIntervalSec,$stripRate,$segLens,$shortStopInterval) = @_;
    
    ## Set the times of the scheduled, typically irregular, events that mark a change in integrator behavior.
	
	## Does NOT include the start of the initial segment, which is not stripped until the expiration of the sink interval.

    PrintSeparator("Setting up seg start t\'s");

    if ($stripRate){
        
        my $tIntervals = pdl($sinkIntervalSec)->glue(0,$segLens/$stripRate);
        $segStartTs = cumusumover($tIntervals);
		$segStartTs = $segStartTs(1:-1);
			# Only include times that require a reduction in the number of segments.
        
        if ($shortStopInterval){
            $segStartTs(1:-1) -= $shortStopInterval;
        }
		
		$segStartTs = DecimalRound($segStartTs);
    }
    else {
        $segStartTs = zeros(0);
    }
    
    if ($verbose>=2){pq($segStartTs)}
    
    return $segStartTs;
}



my ($qs0,$qDots0);

sub SetStartingConfig {
    my ($segLens) = @_;
    
    ## Take the initial line configuration as straight and horizontal, deflected from straight downstream by the specified angle (pos is toward the plus Y-direction).
    
    PrintSeparator("Setting up starting configuration");
    
    my $lineTheta0  = eval($rps->{configuration}{crossStreamAngleDeg})*$pi/180;
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
    #pq($dxs,$dys,$dzs);
    
    
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
    #pq($firstTippetInd);

    
    my $dZs = ($tuckHtIn/$firstTippetInd) * ones($firstTippetInd);
    #pq($dZs);
    #$dZs    /= $dZs(-1);    # Normalize
   # pq($dZs);
    #$dZs    *= $tuckHtIn;
    #pq($dZs);
    $dZs    = $dZs->glue(0,zeros($indsTippet));
    #pq($dZs);
   
    $dzs    += $dZs;
    #pq($dzs);
    
    # Now, readjust the dxs and dys to make the segLens right:
    my $lineDxs     = $dxs(0:$lastLineInd);
    my $lineDys     = $dys(0:$lastLineInd);
    my $oldLineDrs  = sqrt($lineDxs**2 + $lineDys**2);
    #pq($oldLineDrs);

    my $lineDzs     = $dzs(0:$lastLineInd);
    my $lineSegLens	= $segLens(0:$lastLineInd);
    #pq($lineDzs,$lineSegLens);
    
    my $newLineDrs  = sqrt($lineSegLens**2 - $lineDzs**2);
    my $mults    = $newLineDrs/$oldLineDrs;
    pq($newLineDrs,$mults);
    $lineDxs *= $mults;
    $lineDys *= $mults;
    #pq($lineDxs,$lineDys);
    
    #pq($dxs,$dys,$dzs);
    
    # Check:
    my $finalDrs = sqrt($dxs**2+$dys**2+$dzs**2);
    #pq($finalDrs,$segLens);
    
    # Give the tippet segs a negative z-velocity:
    my $tippetVels  = sequence($indsTippet)+1;
    $tippetVels     *= -$tuckVelInPerSec/$tippetVels(-1);
    #pq($tippetVels);
    $indsTippet     = -$indsTippet(-1)+$indsTippet-1;
    #pq($indsTippet);
    
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
my ($Dynams0,$dT0,$dT);
my $shortStopInterval = 0.00;   # Secs.  This mechanism doesn't seem necessary.  See Hamilton::AdjustTrack_STRIPPING().
my %opts_plot;
my ($surfaceVel,$bottomDepth);

my $levelLeaderSinkInPerSec;	# For reporting.
my ($T,$Dynams);
	# Will hold the complete integration record.  I put them up here since $T will be undef'd in SetupIntegration() as a way of indicating that the CastRun() initialization has not yet been done.


sub SetupIntegration {
    
    ## Convert component data to a specific model for use by the fitting function.  Call this function when (re)loading the data as soon as $rps is set, to prepare for calculating the flex.
    
    $timeStr = scalar(localtime);
    
    my($date,$time) = ShortDateTime;
    my $dateTimeShort = sprintf("(%06d_%06d)",$date,$time);
    
    $rps->{file}{save} = '_'.$rps->{line}{identifier}.'_'.$dateTimeShort;
    
    $profileStr     = $rps->{stream}{profileText};
    $profileStr     = substr($profileStr,10); # strip off "profile - "

    
    $bottomDepth				= $rps->{stream}{bottomDepthFt} * $feetToCms;
    $surfaceVel					= $rps->{stream}{surfaceVelFtPerSec} * $feetToCms;
	my $halfVelThickness		= $rps->{stream}{halfVelThicknessFt} * $feetToCms;
    my $surfaceLayerThickness	= $rps->{stream}{surfaceLayerThicknessIn} * $inchesToCms;
    
    my $horizHalfWidth			= $rps->{stream}{horizHalfWidthFt} * $feetToCms;
    my $horizExponent           = $rps->{stream}{horizExponent};
    
    # Show the velocity profile:
    if ($rps->{stream}{showProfile}){
        #        my $count = 101; my $Ys = -(sequence($count+5)/($count-1))*$bottomDepth;
        my $count   = 101;
        my $Zs      = ((10-sequence($count+15))/($count-1))*$bottomDepth;
        
        Calc_VerticalProfile($Zs,$profileStr,$bottomDepth,$surfaceVel,$halfVelThickness,$surfaceLayerThickness,1);
        
        my $Ys  = (sequence(2*$count+1)-$count)/$count;
        $Ys     *= 2* $horizHalfWidth;
        
        Calc_HorizontalProfile($Ys,$horizHalfWidth,$horizExponent,1);
    }
	
    my $nominalG = $rps->{ambient}{nominalG};
    
    # Setup drag for the line segments:
    $dragSpecsNormal    = Str2Vect($rps->{ambient}{dragSpecsNormal});
    $dragSpecsAxial     = Str2Vect($rps->{ambient}{dragSpecsAxial});
    
    # Calculate and print free sink speed:
    if ($leaderStr eq "level"){

        PrintSeparator("Calculating free sink speed");

        my $levelDiam	= $rps->{leader}{diamIn} * $inchesToCms;
        my $levelLen	= 12 * $inchesToCms;
        my $levelMass	= $rps->{leader}{wtGrsPerFt} * $grainsToGms;
        my ($levelLeaderSink,$FDrag,$CDrag,$RE) =
            Calc_FreeSinkSpeed($dragSpecsNormal,$levelDiam,$levelLen,$levelMass);
		$levelLeaderSinkInPerSec = $levelLeaderSink / $inchesToCms;
		
        if ($verbose){
			printf("\n*** Calculated free sink speed of level leader is %.3f (in\/sec) ***\n",$levelLeaderSinkInPerSec);
			printf("*** Drag Coefficient = %.3f, Reynolds Number = %.3f. ***\n\n",$CDrag,$RE);
		}

    } else { $levelLeaderSinkInPerSec = undef}
	
    
    $sinkInterval       = eval($rps->{driver}{sinkIntervalSec});
    $stripRate          = eval($rps->{driver}{stripRateFtPerSec}) * $feetToCms;
	if ($verbose>=3){pq($sinkInterval,$stripRate)}
    
    my $runControlPtr          = \%runControl;
    my $loadedStateIsEmpty     = $loadedState->isempty;
    
    # Temp:
    my $segFluidMultRand    = 0;
    print "FIX segFluidMultRand\n";
    
    # Initialize dynamical variables:
    my $T0			= $rps->{integration}{t0};
    ($qs0,$qDots0)	= SetStartingConfig($segLens);
    #pq($qs0,$qDots0);
    
    my $tuckHtIn        = $rps->{configuration}{tuckHeightFt}*12;
    my $tuckVelInPerSec = $rps->{configuration}{tuckVelFtPerSec}*12;
    #pq($tuckHtIn,$tuckVelInPerSec);

    if ($tuckHtIn or $tuckVelInPerSec){
        AdjustStartingForTuck($tuckHtIn,$tuckVelInPerSec,$segLens);
    }
    
    if ($verbose>=3){pq($qs0,$qDots0)}

    $Dynams0 = $qs0->glue(0,$qDots0);  # Sic.  In my scheme, on initialization, the second half of dynams holds the velocities, not the momenta.
    #pq($Dynams0);
    
    
    $dT0    = eval($rps->{integration}{dt0});
    $dT     = eval($rps->{integration}{plotDt});
    
    if ($verbose>=3){pq($T0,$Dynams0,$dT)}
    if (DEBUG and $verbose>=5){pqInfo($Dynams0)}
    
    SetSubsequentSegStartTs($T0,$sinkInterval,$stripRate,$segLens,$shortStopInterval);
    
    $T      = $T0;  # Not a pdl yet.  Signals run needs initialization.
    
    $paramsStr    = GetLineStr()."\n".GetLeaderStr()."\n".GetTippetStr()."  ".GetFlyStr()."\n".
                    GetAmbientStr()."\n".GetStreamStr()."\n".$integrationStr;
    
    
    %opts_plot = (gnuplot=>$gnuplot,ZScale=>$rps->{integration}{plotZScale});
    #pq(\%opts_plot);

	$T = undef;
	
    # Simply zero rod specific params here.
    Init_Hamilton(  "initialize",
                    $nominalG,0,0,      # Standard gravity, No rod.
                    0,$numSegs,        # No rod.
                    $segLens,$segDiams,
                    $segMasses,$segVols,$segKs,$segCs,
                    zeros(0),zeros(0),
					undef,undef,
                    $flyNomLen,$flyNomDiam,$flyMass,$flyNomDispVol,
                    $dragSpecsNormal,$dragSpecsAxial,
                    $segFluidMultRand,
                    $driverXSpline,$driverYSpline,$driverZSpline,
                    undef,undef,undef,
                    $driverStartTime,$driverEndTime,
                    undef,undef,
                    $T0,$Dynams0,$dT0,$dT,
                    $runControlPtr,$loadedStateIsEmpty,
                    $profileStr,$bottomDepth,$surfaceVel,
                    $halfVelThickness,$surfaceLayerThickness,
                    $horizHalfWidth,$horizExponent,
                    $sinkInterval,$stripRate);
    
    return 1;
}



my (%opts_GSL,$t0_GSL,$t1_GSL,$dt_GSL,);
my ($init_numSegs,$numSegs_GSL);
my $elapsedTime_GSL;
my ($finalT,$finalState);
my ($plotNumRodSegs,$plotErrMsg);
my ($plotTs,$plotXs,$plotYs,$plotZs);
my ($plotXLineTips,$plotYLineTips,$plotZLineTips);
my ($plotXLeaderTips,$plotYLeaderTips,$plotZLeaderTips);
my $plotBottom;

my $strippingEnabled;
# These include the handle butt.

my $theseDynams_GSL;
my $segNomLens;		# Probably not necessary.

$doRun = \&DoRun;	# Set global pointer for use by RCommonInterface.

sub DoRun {
    
    ## Do the integration.  Either begin run or continue. if $T is not a PDL we are initializing a run.  The initialization block of this function turns $T into a pdl, and it, plus times glued below it, store the reported results from the solver.  Parallel to $T is the pdl matrix $Dynams whose rows store the values of the dynamic variables associated with the reported times.
	
	# In general, this function will store just results corresponding to the uniform vector of times separated by the interval $dTPlot.  There is one exception to this:  If the solver makes a planned stop at an event time that is not one of the uniform times, its value and the associated dynamical values will be temporarily stored as the last entries in $T and $Dynams.  I do this so that if there is a subsequent user interrupt before the next uniform time, the run can continue from the event data, and not need to go back to the uniform time before that.  This is both more user friendly, and easier to implement.
	
	# When we next obtain a uniform data time and dynamical variables, the temporary values will be removed before the subsequent times and values are appended.
	
	# User interrupts are generated only by means of the PAUSE button on the control panel.  When one is caught, this function stores any good data the solver returns and plots all the uniform-interval data that has previously been collected by all the subsequent runs.  After an interrupt, and on a subsequent CONTINUE, this whole function will be run again, but a small, partial initialization that I call a restart.  The new run takes up where the previous one left off.  NOTE that the PAUSE button will only be reacted to during a call to DE, so in particular, while the solver is running.
	
	## To avoid ambiguity from comparisons of doubles, I have reduced all the timings passed to and from the integrator to multiples of secs/10000.  This was done in CheckParams() using DecimalRound().
    
	
    my $JACfac;
    
    if (ref($T) ne 'PDL'){
        
		PrintSeparator("*** Running the GSL solver ***",0,$verbose>=2);
	
		$init_numSegs		= $numSegs;
		$numSegs_GSL		= $init_numSegs;

        $elapsedTime_GSL    = 0;

        $t0_GSL             = Get_T0();

        my $t1				= $rps->{integration}{t1};   # Requested end
        $dt_GSL             = $dT;
        my $lastStep_GSL	= DecimalFloor(($t1-$t0_GSL)/$dt_GSL);
        $t1_GSL             = $t0_GSL+$lastStep_GSL*$dt_GSL;    # End adjusted to keep the reported step intervals constant.
		if ($verbose>=2 and $t1 != $t1_GSL){print "Reducing stop time to last uniform step, from $t1 to $t1_GSL\n"}
        

        $Dynams             = Get_DynamsCopy(); # This includes good initial $ps.
        if($verbose>=3){pq($t0_GSL,$t1_GSL,$dt_GSL,$Dynams)}
        
        $strippingEnabled	= ($segStartTs->isempty) ? 0 : 1;
			# Yes if we will eventually strip
        #pq($segStartTs,$strippingEnabled);
		
		if ($strippingEnabled){
			# Truncate and adjust the events list so that t1 becomes the final event:

			my $iEvents	= which($segStartTs < $t1_GSL);
			$segStartTs	= ($segStartTs->isempty) ? zeros(0) : $segStartTs($iEvents);
			$segStartTs	= $segStartTs->glue(0,pdl($t1_GSL));
			#print "DoRun init: ";pq($segStartTs);
			if (DEBUG and $verbose>=3){pq($segStartTs)}
			
			# No restart needed here because even if we start stripping immediately, the initial segment will not be used up for a while.
         }
		
        $segNomLens     = $segLens;
        
        my $h_init  = eval($rps->{integration}{dt0});
        %opts_GSL   = (type=>$rps->{integration}{stepperName},h_init=>$h_init);
        if ($verbose>=3){pq(\%opts_GSL)}
            
        $T = pdl($t0_GSL);   # To indicate that initialization has been done.  Prevents repeated initializations even if the user interrups during the first plot interval.
        #pq($T);print "init\n";

        if ($verbose>=2){print "Solver startup can be especially slow.  BE PATIENT.\n"}
        else {print "RUNNING SILENTLY, wait for return, or hit PAUSE to see the results thus far.\n"}
    }

    my $nextStart_GSL	= $T(-1)->sclr;
	if (DEBUG and $verbose>=2){printf( "(Re)entering Run:\tt=%.5f\n",$nextStart_GSL)}

	if (!$numSegs_GSL){die "Called with no segs left.\nStopped"}
 	my $nextDynams_GSL	= StripDynams($Dynams(:,-1),$numSegs_GSL);
	
    if ($verbose>=3){
        $JACfac = JACget();
        pq($JACfac);
    }
    
    # Run the solver:
    my $timeStart = time();
    my $tStatus = 0;
    my $tErrMsg = '';;
    my ($interruptT,$interruptDynams);

    
    # Also, error scaling options. These all refer to the adaptive step size contoller which is well documented in the GSL manual.
    
    # epsabs and epsrel the allowable error levels (absolute and relative respectively) used in the system. Defaults are 1e-6 and 0.0 respectively.
    
    # a_y and a_dydt set the scaling factors for the function value and the function derivative respectively. While these may be used directly, these can be set using the shorthand ...
    
    # scaling, a shorthand for setting the above option. The available values may be y meaning {a_y = 1, a_dydt = 0} (which is the default), or yp meaning {a_y = 0, a_dydt = 1}. Note that setting the above scaling factors will override the corresponding field in this shorthand.
        
    ## See https://metacpan.org/pod/PerlGSL::DiffEq for the solver documentation.
    
    # I want the solver to return uniform steps of size $dt_GSL.  Thus, in the case of off-step returns (user or stripper interrupts) I need to make an additional one-step correction call to the solver, and edit its returns appropriately.  The correction step is always made with the new configuration and terminates on the next step.
    
    ## NextStart is always last report.  Also, each scheduled restart will be a last report.
	my $numSolverCalls = 0;
    while ($nextStart_GSL < $t1_GSL) {
        
        my $thisStart_GSL = $nextStart_GSL;
        if (DEBUG and $verbose>=2){printf("\nt=%.4f   ",$thisStart_GSL)}

		my @tempArray = $nextDynams_GSL->list;
		my $theseDynams_GSL_Ref = \@tempArray;	# Can't figure out how to do this in 1 go.
		#my $reftype = ref($theseDynams_GSL_Ref);
		#pq($reftype); die;
        
        my $thisStop_GSL;
        my $thisNumSteps_GSL;
        my $nextSegStart_GSL;
		my $startIsUniform;
		my $startIsEvent;
        my $stopIsUniform;
        my $solution;
        
        if (!$strippingEnabled){
			# No events, at least between t0 and t1.  Uniform starts and stops only.  On user interrupt, starts at last reported time.
            $thisStop_GSL		= $t1_GSL;
            $thisNumSteps_GSL	= DecimalFloor(($thisStop_GSL-$thisStart_GSL)/$dt_GSL);
            $stopIsUniform		= 1;

			if (DEBUG and $verbose>=2){print "thisStop_GSL=$thisStop_GSL,stopIsUniform=$stopIsUniform\n"}
        }
        else {    # There are restarts.

			# See where we are relative to them:
			my $iRemains	= which($segStartTs >= $thisStart_GSL);
				# Will never be empty since t1 is an event, and we wouldn't be in the loop unless this time is less than that.
			$nextSegStart_GSL	= $segStartTs($iRemains(0))->sclr;
				# Never T0.

			# Are we actually starting at the next (actually this) event?
			if ($thisStart_GSL == $nextSegStart_GSL){
				$startIsEvent	= 1;
				$nextSegStart_GSL	= $segStartTs($iRemains(1))->sclr;
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
					= DecimalFloor(($nextSegStart_GSL-$thisStart_GSL)/$dt_GSL);
                if ($thisNumSteps_GSL){     # Make whole steps to just before the next restart.
                    $thisStop_GSL   = $thisStart_GSL + $thisNumSteps_GSL*$dt_GSL;
                    $stopIsUniform  = 1;
                } else {    # Need to make a single partial step to take us to the next event.  This should NOT take us to the end, since we started uniform and the adjusted t1 is also uniform.
                    $thisStop_GSL		= $nextSegStart_GSL;
                    $thisNumSteps_GSL   = 1;
                    $stopIsUniform
						= ($thisStop_GSL == $lastUniformStop+$dt_GSL) ? 1 : 0;
						# It might be a uniform event.
                }
            }
            else { # start is not uniform, so make no more than one step.
                
                $thisNumSteps_GSL       = 1;
                
                my $nextUniformStop = $lastUniformStop + $dt_GSL;
                if ($nextSegStart_GSL < $nextUniformStop) {
                    $thisStop_GSL   = $nextSegStart_GSL;
                    $stopIsUniform  = 0;
                } else {
                    $thisStop_GSL   = $nextUniformStop;
                    $stopIsUniform  = 1;
                }
            }

			if (DEBUG and $verbose>=2){print "startIsEvent=$startIsEvent,nextSegStart_GSL=$nextSegStart_GSL,thisStop_GSL=$thisStop_GSL\nlastUniformStop=$lastUniformStop,startIsUniform=$startIsUniform,stopIsUniform=$stopIsUniform\n"}
        }
        
        

        if ($verbose>3){print "\n SOLVER CALL: start=$thisStart_GSL, end=$thisStop_GSL, nSteps=$thisNumSteps_GSL\n\n"}
        #if (1){print "\n SOLVER CALL: start=$thisStart_GSL, end=$thisStop_GSL, nSteps=$thisNumSteps_GSL\n\n"}

        if($thisStart_GSL >= $thisStop_GSL){die "ERROR: Detected bad integration bounds.\nStopped"}
		
		#print "Before solver, thisStart_GSL=$thisStart_GSL\n";
		

        $solution = pdl(ode_solver([\&DEfunc_GSL,\&DEjac_GSL],[$thisStart_GSL,$thisStop_GSL,$thisNumSteps_GSL],$theseDynams_GSL_Ref,\%opts_GSL));
		# NOTE that my solver does not return the initial solution, but I already know that.
		$numSolverCalls++;
		
		#pq($solution);

		# Immediately decimal round the returned times so that there will be no ambiguities in the comparisons below:
		my $returnedTs = $solution(0,:)->copy;
		#pq($numSolverCalls);
		#pq($returnedTs);
		#my ($returnedNSegs,$unused) = $solution->dims;
		#$returnedNSegs = ($returnedNSegs-1)/6;
		#pq($returnedNSegs);
		
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

		#pq($solution);
		
        $nextStart_GSL  = $solution(0,-1)->sclr;    # Latest report time.
        $nextDynams_GSL = $solution(1:-1,-1)->flat;
		
		if (DEBUG and $verbose>=3){print "END_TIME=$nextStart_GSL\nEND_DYNAMS=$nextDynams_GSL\n\n"}
		
        #my $beginningNewSeg =
		#	($strippingEnabled and
		#		($nextStart_GSL == $nextSegStart_GSL) or
		#		($nextStart_GSL == $t0_GSL) ) ? 1 : 0;

        my $beginningNewSeg =
			($strippingEnabled and
				($nextStart_GSL == $nextSegStart_GSL) ) ? 1 : 0;

        #my $nextJACfac;
        #if ($beginningNewSeg and $nextStart_GSL > $segStartTs(0)){
        if ($beginningNewSeg and $nextStart_GSL >=  $segStartTs(0)){
            # Must reduce the number of segs if not (re)starting the initial segment. T0 is not in the segStarts list.
            ($numSegs_GSL,$nextDynams_GSL) = StripSolution($solution(:,-1)->flat);
			#pq($numSegs_GSL,$nextDynams_GSL);
        }
		
		if (DEBUG and $verbose>=4){pq($nextStart_GSL,$nextDynams_GSL)}
 
         # There  is always at least one time (starting) in solution.  Never keep the starting data:
        my ($nRows,$nTimes) = $solution->dims;
        #pq($nRows,$nTimes);
		
        if ($nextStart_GSL == $thisStop_GSL) { # Got to the planned end of block run (so there is at least 2 rows.
		
			# We will keep the stop data, whether or not the stop was uniform.  However if it was not, we'll get rid of it next pass through the loop.
		
			# However, if the start was not uniform, remove the last stored data row, which we can do because we have something more recent to start with next time:
			if (!$startIsUniform){
				$T		= $T(0:-2);
				$Dynams	= $Dynams(:,0:-2);
			}
        }
		#pq($solution);
        
        # In any case, we never keep the run start data:
        $solution   = ($nTimes <= 1) ? zeros($nRows,0) : $solution(:,1:-1);

        my ($ts,$paddedDynams) = PadSolution($solution,$init_numSegs);
		
		$T = $T->glue(0,$ts);
		#pq($T);
		$Dynams = $Dynams->glue(1,$paddedDynams);
		if (DEBUG and $verbose>=6){pq($T,$Dynams)}
		
        if ($nextStart_GSL < $t1_GSL and $numSegs_GSL and $tStatus >= 0) {
            # Either no error, or there was a user interrupt.
            
            Init_Hamilton("restart_swing",$nextStart_GSL,$nextDynams_GSL,$beginningNewSeg);
        }

        if (!$tStatus and !$numSegs_GSL){
            $tErrMsg = "Stripped all the line in.\n";
        }
        if ($tStatus or !$numSegs_GSL){last}
    }
    
    my $timeEnd = time();
    $elapsedTime_GSL += $timeEnd-$timeStart;
    
    if ($verbose>=3){
        my $JACfac = JACget();
        pq($JACfac);
    }
    
    
    if (DEBUG and $verbose>=6){print "After run\n";pq($T,$Dynams)};
	
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

        if (DEBUG and $verbose>=6){pq($tXs,$tYs,$tZs)}
        
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
            if (DEBUG and $verbose>=6){pq($tXs,$tYs,$tZs)}
            
            
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
            
            if (DEBUG and $verbose>=6){
                    print "Appending interrupt data\n";
                    pq($tt,$tXs,$tYs,$tZs);
            }
        #        }
    }
    
    
    if (DEBUG and $verbose>=6){pq($plotTs,$plotXs,$plotYs,$plotZs,$plotRs)}
    if (DEBUG and $verbose>=6){pq($plotXLineTips,$plotYLineTips,$plotZLineTips,$plotXLeaderTips,$plotYLeaderTips,$plotZLeaderTips)}
    
    
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
    
    my $titleStr = "RSwing - " . $dateTimeLong;
    
    $plotNumRodSegs = 0;
    $plotBottom     = -$bottomDepth;   # Passing actual z coordinate.
	

    RCommonPlot3D('window',$rps->{file}{save},$titleStr,$paramsStr,
    $plotTs,$plotXs,$plotYs,$plotZs,$plotXLineTips,$plotYLineTips,$plotZLineTips,$plotXLeaderTips,$plotYLeaderTips,$plotZLeaderTips,$plotNumRodSegs,$plotBottom,$plotErrMsg,$verbose,\%opts_plot);
    
    
    # If integration has completed, tell the caller:
    if ($tPlot>=$t1_GSL or $tStatus < 0 or !$numSegs_GSL) {
        if ($tStatus < 0){print "\n";pq($tStatus,$tErrMsg)}
        if (!$numSegs_GSL){print "\n$tErrMsg"}
        &{$runControl{callerStop}}();
    }
    
}


sub UnpackDynams {
    my ($dynams) = @_;

    my $numSegs    = ($dynams->dim(0))/6;

    my $dxs         = $dynams(0:$numSegs-1,:);
    my $dys         = $dynams($numSegs:2*$numSegs-1,:);
    my $dzs         = $dynams(2*$numSegs:3*$numSegs-1,:);

    my $dxps      = $dynams(3*$numSegs:4*$numSegs-1,:);
    my $dyps      = $dynams(4*$numSegs:5*$numSegs-1:);
    my $dzps      = $dynams(5*$numSegs:-1,:);
    
    return ($dxs,$dys,$dzs,$dxps,$dyps,$dzps);
}


sub StripDynams {
    my ($dynams,$numKeep) = @_;
	
    my $numSegs    = ($dynams->dim(0))/6;
	if ($numSegs == $numKeep){ return $dynams}
	
	my ($dxs,$dys,$dzs,$dxps,$dyps,$dzps) = UnpackDynams($dynams);
	
    my $strippedDynams = $dxs(-$numKeep:-1,:)->glue(0,$dys(-$numKeep:-1,:))->glue(0,$dzs(-$numKeep:-1,:))->glue(0,$dxps(-$numKeep:-1,:))->glue(0,$dyps(-$numKeep:-1,:))->glue(0,$dzps(-$numKeep:-1,:));
	
	return $strippedDynams;
}


sub UnpackSolution {
    my ($solution) = @_;
	
    my $ts		= $solution(0,:);
	my $dynams	= $solution(1:-1,:);
	
	my ($dxs,$dys,$dzs,$dxps,$dyps,$dzps) = UnpackDynams($dynams);
	
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



sub StripSolution {
    my ($solution) = @_;
    
    if ($solution->dim(1) != 1){die "ERROR:  StripSolution requires exactly one row.\nStopped"}
    
    my ($ts,$dxs,$dys,$dzs,$dxps,$dyps,$dzps) = UnpackSolution($solution->flat);
    
    if ($dxs->nelem <= 1){
        return(0,zeros(0));
    }
    
    my $strippedDynams = $dxs(1:-1)->glue(0,$dys(1:-1))->glue(0,$dzs(1:-1))->
                            glue(0,$dxps(1:-1))->glue(0,$dyps(1:-1))->glue(0,$dzps(1:-1));
    
    my $numSegs = $strippedDynams->nelem/6;
    return ($numSegs,$strippedDynams->flat);
    
}

        
sub UnpackQsFromDynams {
    my ($tDynams) = @_;
    
    if ($tDynams->dim(1) != 1){die "ERROR:  \$tDynams must be a vector.\nStopped"}
    
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
    
    if (DEBUG and $verbose>=6){print "Calc_Qs:\n Xs=$Xs\n Ys=$Ys\n Zs=$Zs\n drs=$drs\n"}

    my ($XLineTip,$YLineTip,$ZLineTip,$XLeaderTip,$YLeaderTip,$ZLeaderTip);
    if ($nargin > 2){
        ($XLineTip,$YLineTip,$ZLineTip) =
            Calc_QOffset($t,$Xs,$Ys,$Zs,$drs,$lineTipOffset);
    }
    if ($nargin > 3){
        ($XLeaderTip,$YLeaderTip,$ZLeaderTip)  =
            Calc_QOffset($t,$Xs,$Ys,$Zs,$drs,$leaderTipOffset);
    }
        
    if (DEBUG and $verbose>=6){pq($XLineTip,$YLineTip,$ZLineTip,$XLeaderTip,$YLeaderTip,$ZLeaderTip)}
	
    return ($Xs,$Ys,$Zs,$drs,$XLineTip,$YLineTip,$ZLineTip,$XLeaderTip,$YLeaderTip,$ZLeaderTip);
}


sub Calc_QOffset {
    my ($t,$Xs,$Ys,$Zs,$drs,$offset) = @_;

    ## For plotting line and leader tip locations. Expects padded data. Note that the fractional position in the segs should be based on nominal seg lengths, since these positions stretch and contract with the material.  This means, in particular, I need to know the time to (re)compute the nominal active strip seg length.
    
    #pq($t,$Xs,$Ys,$drs,$offset);

    my $tRemainingSegs  = ($drs != 0); # sic
    my $tSegNomLens     = $segNomLens * $tRemainingSegs; # Deal with the padding.
    
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
    $str .= " NomWt,NomDiam,CoreDiam=($rps->{line}{nomWtGrsPerFt},$rps->{line}{nomDiamIn},$rps->{line}{coreDiamIn}); ";
    $str .= " Len==$lineLenFt; ";
    $str .= " Mods(elastic,damping)=($rps->{line}{coreElasticModulusPSI},$rps->{line}{dampingModulusPSI})";

    return $str;
}


sub GetLeaderStr {
    
    my $sinkStr = (defined($levelLeaderSinkInPerSec))?
                sprintf(" CALC\'D SINK=%.3f;",$levelLeaderSinkInPerSec):"";
    
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
    
    my $str = "AMBIENT: Gravity=$rps->{ambient}{nominalG}; ";
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



# SPECIFIC PLOTTING FUNCTIONS ======================================

sub PlotDriverSplines {
    my ($numTs,$driverTStart,$driverTEnd,$driverXSpline,$driverYSpline,$driverZSpline,$plot3D) = @_;
	
	## Expects lengths in cms.
	
    my ($dataXs,$dataYs,$dataZs) = map {zeros($numTs)} (0..2);
	
	print "In PlotDriverSplines\n";
	pq($driverTs);
	
    my $dataTs = $driverTStart+sequence($numTs)*($driverTEnd-$driverTStart)/($numTs-1);
    pq($dataTs);

    for (my $ii=0;$ii<$numTs;$ii++) {

        my $tt = $dataTs($ii)->sclr;

        $dataXs($ii) .= $driverXSpline->evaluate($tt);
        $dataYs($ii) .= $driverYSpline->evaluate($tt);
        $dataZs($ii) .= $driverZSpline->evaluate($tt);
    
    }
	
	# Convert to feet:
	$dataXs /= $feetToCms;
	$dataYs /= $feetToCms;
	$dataZs /= $feetToCms;
    pq($dataXs,$dataYs,$dataZs);

    my %opts;
	if (!$plot3D){
		%opts = (gnuplot=>$gnuplot);
    	Plot($dataTs,$dataXs,"X Splined",$dataTs,$dataYs,"Y Splined",$dataTs,$dataZs,"Z Splined","Splines as Functions of Time",\%opts);
	}
	else {
		#print "A\n";
        %opts = (gnuplot=>$gnuplot,xlabel=>"x-axis(ft)",ylabel=>"y-axis(ft)",zlabel=>"z-axis(ft)");
        Plot3D($dataXs,$dataYs,$dataZs,"Splined Rod Tip Track (ft)",\%opts);
		#print "B\n";
	}
	print "Leaving PlotDriverSplines\n";
}


$doSave = \&DoSave;	# Set global pointer for use by RCommonInterface.

sub DoSave {
    my ($filename) = @_;

    my($basename, $dirs, $suffix) = fileparse($filename);
#pq($basename,$dirs$suffix);

    $filename = $dirs.$basename;
    if ($verbose>=2){print "Saving to file $filename\n"}

    my $titleStr = "RSwing - " . $dateTimeLong;

    $plotNumRodSegs = 0;
    if ($rps->{integration}{savePlot}){
        RCommonPlot3D('file',$dirs.$basename,$titleStr,$paramsStr,
                    $plotTs,$plotXs,$plotYs,$plotZs,$plotXLineTips,$plotYLineTips,$plotZLineTips,$plotXLeaderTips,$plotYLeaderTips,$plotZLeaderTips,$plotNumRodSegs,$plotBottom,$plotErrMsg,$verbose,\%opts_plot);
    }

#pq($plotTs,$plotXs,$plotYs,$plotZs);
                   
    if ($rps->{integration}{saveData}){
        RCommonSave3D($dirs.$basename,$rSwingOutFileTag,$titleStr,$paramsStr,
        $plotTs,$plotXs,$plotYs,$plotZs,$plotXLineTips,$plotYLineTips,$plotZLineTips,$plotXLeaderTips,$plotYLeaderTips,$plotZLeaderTips,$plotNumRodSegs,$plotBottom,$plotErrMsg,
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

__END__


=head1 NAME

RSwing3D - The principal organizer of the RHexSwing3D program.  Sets up and runs the GSL ode solver and plots and saves its output.

=head1 SYNOPSIS

  use RSwing3D;
 
=head1 DESCRIPTION

The functions in this file are used pretty much in the order they appear to gather and check parameters entered in the control panel and to load user selected specification files, then to build a line and stream model which is used to initialize the hamilton step function DE().  The definition of DE() requires nearly all the functions contained in the RHexHamilton3D.pm module.  A wrapper for the step function is passed to the ode solver, which integrates the associated hamiltonian system to simulate the swing dynamics.  After the run is complete, or if the user interrupts the run via the pause or stop buttons on the control panel, code here calls RCommonPlot3D.pm to create a 3D display of the results up to that point. When paused or stopped, the user can choose to save the integration results to .eps or .txt files, or both.

=head2 EXPORT

The principal exports are DoSetup, DoRun, and DoSave.  All the exports are used
only by RHexSwing3D.pl

=head1 AUTHOR

Rich Miller, E<lt>rich@ski.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2019 by Rich Miller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.28.1 or,
at your option, any later version of Perl 5 you may have available.

=cut





