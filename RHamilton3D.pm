# RHamilton3D.pm

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


package RHamilton3D;

use warnings;
use strict;

our $VERSION='0.01';

use Exporter 'import';
our @EXPORT = qw(DEBUG $verbose $debugVerbose $restoreVerbose $reportVerbose Calc_FreeSinkSpeed Init_Hamilton Get_T0 Get_dT Get_movingAvDt Get_TDynam Get_DynamsCopy Calc_Driver Calc_VerticalProfile Calc_HorizontalProfile Get_Tip0 DEfunc_GSL DEjac_GSL DEset_Dynams0Block DE_GetStatus DE_GetErrMsg DE_GetCounts JACget AdjustHeldSeg_HOLD Get_ExtraOutputs);

use Carp;

use Time::HiRes qw (time alarm sleep);
use Switch;
use File::Basename;
use Math::Spline;
use Math::Round;

use PDL;
    # Import main PDL module (see PDL.pm for equivalents).  In particular, imports PDL::Math, which redefines many POSIX math functions.  To get the original, call POSIX::aFunction.

use PDL::NiceSlice;
use PDL::AutoLoader;    # MATLAB-like autoloader.
use PDL::Options;       # Good to keep in mind.

use RUtils::Print;
use RUtils::Plot;
use RUtils::NumJac;
use RUtils::Brent;

use RCommon;
use RCommonPlot3D;


# Code ==================================

# Variables set here from args to SetupHamilton():
my ($mode,
    $nominalG,$rodLength,$actionLength,
    $numRodSegs,$init_numLineSegs,
    $init_segLens,$init_segDiams,
    $init_segMasses,$init_segVols,$init_segKs,$init_segCs,
	$rodBendTorqueKs, $rodBendTorqueCs,
	$holdingK, $holdingC,
    $init_flyNomLen,$init_flyNomDiam,$init_flyMass,$init_flyDispVol,
    $dragSpecsNormal,$dragSpecsAxial,
    $segFluidMultRand,
    $driverXSpline,$driverYSpline,$driverZSpline,
    $driverDXSpline,$driverDYSpline,$driverDZSpline,
    $frameRate,$driverStartTime,$driverEndTime,
    $tipReleaseStartTime,$tipReleaseEndTime,
    $T0,$Dynams0,$dT0,$dT,
    $runControlPtr,$loadedStateIsEmpty,
    $profileStr,$bottomDepth,$surfaceVel,$halfVelThickness,
    $horizHalfWidth,$horizExponent,
    $surfaceLayerThickness,
    $sinkInterval,$stripRate);


my ($DE_status,$DE_errMsg);
# The ode_solver returns status -1 on error, but does not give the value to me.  In any case, I avoid that value.  I return 0 if no error, -2 on bottom error, and 1 on user interrupt.

# Working copy (if stripping, cut down from the initial larger pdls, and subsequently, possibly with first seg readjusted in time):
my ($segLens,$segDiams,
    $segMasses,$segVols,$segKs,$segCs,
    $numLineSegs,$lineSegKs,$lineSegCs,
    $flyNomLen,$flyNomDiam,$flyMass,$flyDispVol);

my ($rodSegLens,$lineSegLens,$init_lineSegNomLens);
my ($Masses,$MassesDummy1,$outboardMassSums,$outboardMassSumsFixed);
my $lowerTri;

my ($calculateFluidDrag,$airOnly);
my $dampOnlyOnExpansion;

my $holding;	# Holding state currently unused.
my ($stripping,$stripStartTime);
	# 0 disabled, -1 enabled but not active, 1 active.
my ($thisSegStartT,$lineSeg0LenFixed,
    $lineSeg0MassFixed,$lineSeg0VolFixed,
    $lineSeg0KFixed,$lineSeg0CFixed);
my ($HeldSegLen,$HeldSegK,$HeldSegC);
#my $init_verbose;
my ($DE_lastSteppingCall,$DE_lastSteppingT,$DE_maxAttainedT,$DE_movingAvDt);


my ($tDynam,$dynams);    # My global copy of the args the stepper passes to DE.


sub Init_Hamilton {
    $mode = shift;
    
    if ($mode eq "initialize"){
        
        my ($Arg_nominalG,$Arg_rodLength,$Arg_actionLength,
            $Arg_numRodSegs,$Arg_numLineSegs,
            $Arg_segLens,$Arg_segDiams,
            $Arg_segMasses,$arg_segVols,$Arg_segKs,$Arg_segCs,
            $Arg_rodBendTorqueKs,$Arg_rodBendTorqueCs,
            $Arg_holdingK,$Arg_holdingC,
            $Arg_flyNomLen,$Arg_flyNomDiam,$Arg_flyMass,$Arg_flyDispVol,
            $Arg_dragSpecsNormal,$Arg_dragSpecsAxial,
            $Arg_segFluidMultRand,
            $Arg_driverXSpline,$Arg_driverYSpline,$Arg_driverZSpline,
            $Arg_driverDXSpline,$Arg_driverDYSpline,$Arg_driverDZSpline,
            $Arg_frameRate,$Arg_driverStartTime,$Arg_driverEndTime,
            $Arg_tipReleaseStartTime,$Arg_tipReleaseEndTime,
            $Arg_T0,$Arg_Dynams0,$Arg_dT0,$Arg_dT,
            $Arg_runControlPtr,$Arg_loadedStateIsEmpty,
            $Arg_profileStr,$Arg_bottomDepth,$Arg_surfaceVel,
            $Arg_halfVelThickness,$Arg_surfaceLayerThickness,
            $Arg_horizHalfWidth,$Arg_horizExponent,
            $Arg_sinkInterval,$Arg_stripRate) = @_;
        
        PrintSeparator ("Initializing stepper code",2);
        
        $nominalG					= $Arg_nominalG;
        $rodLength                  = $Arg_rodLength;
        $actionLength               = $Arg_actionLength;
        $numRodSegs                 = $Arg_numRodSegs;
        $init_numLineSegs           = $Arg_numLineSegs;
        $init_segLens               = $Arg_segLens->copy;
		$init_segDiams				= $Arg_segDiams->copy;
        $init_segMasses				= $Arg_segMasses->copy;
        $init_segVols				= $arg_segVols;
        $init_segKs                 = $Arg_segKs->copy;		# stretch, both rod, line
        $init_segCs                 = $Arg_segCs->copy;		# stretch, both rod, line
		$rodBendTorqueKs			= $Arg_rodBendTorqueKs->copy;
		$rodBendTorqueCs			= $Arg_rodBendTorqueCs->copy;
		$holdingK               	= $Arg_holdingK;
		$holdingC               	= $Arg_holdingC;
        $init_flyNomLen             = pdl($Arg_flyNomLen);
        $init_flyNomDiam            = pdl($Arg_flyNomDiam);
        $init_flyMass				= pdl($Arg_flyMass);
        $init_flyDispVol			= pdl($Arg_flyDispVol);
        $dragSpecsNormal            = $Arg_dragSpecsNormal;
        $dragSpecsAxial             = $Arg_dragSpecsAxial;
        $segFluidMultRand           = $Arg_segFluidMultRand;
        $driverXSpline              = $Arg_driverXSpline;
        $driverYSpline              = $Arg_driverYSpline;
        $driverZSpline              = $Arg_driverZSpline;
        $driverDXSpline             = $Arg_driverDXSpline;
        $driverDYSpline             = $Arg_driverDYSpline;
        $driverDZSpline             = $Arg_driverDZSpline;
        $frameRate                  = $Arg_frameRate;
        $driverStartTime            = $Arg_driverStartTime;
        $driverEndTime              = $Arg_driverEndTime;
        $tipReleaseStartTime        = $Arg_tipReleaseStartTime;
        $tipReleaseEndTime          = $Arg_tipReleaseEndTime;
        $T0                         = $Arg_T0;
        $Dynams0                    = $Arg_Dynams0->copy;
        $dT0                        = $Arg_dT0;
        $dT                         = $Arg_dT;
        $runControlPtr              = $Arg_runControlPtr;
        $loadedStateIsEmpty         = $Arg_loadedStateIsEmpty;
        $profileStr                 = $Arg_profileStr;
        $bottomDepth				= $Arg_bottomDepth;
        $surfaceVel					= $Arg_surfaceVel;
        $halfVelThickness			= $Arg_halfVelThickness;
        $surfaceLayerThickness		= $Arg_surfaceLayerThickness;
        $horizHalfWidth				= $Arg_horizHalfWidth;
        $horizExponent              = $Arg_horizExponent;
        $sinkInterval               = $Arg_sinkInterval;
        $stripRate                  = $Arg_stripRate;
        
        
        ### NOTE: When mode="initialize", and $loadedStateIsEmpty=true, the second half of $Dynams0 must contain initial velocities ($qDots), rather than the usual conjugate momenta ($ps).
        
        
        # I will always "initialize" as though there is no stripping or holding, and then let subsequent calls to "restart_swing" and "restart_cast" deal with those states.  This lets me have the caller do the appropriate adjustments to $Dynams0 (so $dynams).
 
		PrintSeparator("Initializing",3);
		
        #$holding    = 0;
        $stripping = 0;
        if (defined($sinkInterval)){
            if (!defined($stripRate)){die "ERROR:  In stripping mode, both sinkInterval and stripRate must be defined.\nStopped"}
			$stripStartTime = $T0 + $sinkInterval;
			$thisSegStartT  = $T0;
			if ($verbose>=2){pq($sinkInterval,$stripRate,$T0,$stripStartTime)}

			if ($stripRate > 0){
				if ($T0 < $stripStartTime){$stripping = -1}
				else {$stripping = 1}
			}
        }

		
		if ($verbose>=3){pq($T0,$stripping)}

        if (!defined($tipReleaseStartTime) or !defined($tipReleaseEndTime)){
            # Turn off release delay mechanism:
            $tipReleaseStartTime    = $T0 - 1;
            $tipReleaseEndTime      = $T0 - 0.5;
        }
        
        # Initialize other things directly from the passed params:
		$numLineSegs		= $init_numLineSegs;
		$init_segMasses(-1)	+= $init_flyMass;
		
        $airOnly = (!defined($profileStr))?1:0;    # Strange that it requires this syntax to get a boolean.
		
		if (!$airOnly){
			#pq($init_segVols,$init_flyDispVol);
			$init_segVols(-1)	+= $init_flyDispVol;
		}
        
        $calculateFluidDrag = any($dragSpecsNormal->glue(0,$dragSpecsAxial));

		if (any($init_segCs<0)){
			$dampOnlyOnExpansion = 1;
			$init_segCs = abs($init_segCs);
		}
		else {$dampOnlyOnExpansion = 0}
        
        DE_InitCounts();
        DE_InitExtraOutputs();
		
        #JAC_FacInit();
    }
    
    elsif ($mode eq "restart_swing") {
        my ($Arg_restartT,$Arg_Dynams,$Arg_beginningNewSeg) = @_;
		
		## To be called only after the first segment has been used up by stripping.
        
        PrintSeparator("In swing, re-initializing stepper,",3);
        
        my $restartT    = $Arg_restartT;
        $Dynams0        = $Arg_Dynams->copy;
		$numLineSegs	= $Dynams0->nelem/6;
		
        if ($Arg_beginningNewSeg){$thisSegStartT = $restartT}
        
        if (!$numLineSegs){die "ERROR:  Stripping only makes sense if there is at least one (remaining) line segment.\nStopped"}

		# Need to reset $stripping to handle case where DE switched to 1, but restart after user interrupt lowered time back to before strip start:
		if ($stripRate > 0){
			if ($restartT < $stripStartTime){$stripping = -1}
			else {$stripping = 1}
		}
		else {$stripping = 0}
		#if ($verbose>=2){print("Restarting: ");pq($Arg_beginningNewSeg,$restartT,$thisSegStartT,$stripping)}
		
        if ($verbose>=3){pq($stripStartTime,$restartT,$thisSegStartT,$Arg_beginningNewSeg,$stripping)}
    }
    elsif ($mode eq "restart_cast") {
        my ($Arg_restartT,$Arg_Dynams) = @_;

		PrintSeparator ("In cast, re-initializing stepper,",3);
		
		# "No real cast reset is necessary for holding, but am keeping this here to help if we ever implement hauling, which would use the events mechanism.
		
		# This restart is now only minimally used, to reset the status and errMsg flags.
		
		if ($verbose>=3){pq($dynams,$Arg_restartT,$Arg_Dynams)}
        ## This is how I conceive of tip holding: The two tip segment variables (original dxs(-1),dys(-1)) are no longer dynamical, but become dependent on all the remaining (inboard) ones, since the tip outboard node (the fly) is fixed in space, and the tip inboard node is determined by all the inboard variables.  However, the remaining variables are still influenced by the tip segment in a number of ways:  The segment cg is still moved by the inboard variables, and the amount is exactly half of the motion of the tip inboard node, since the fly node contributes nothing.  This contributes both inertial and frictional forces. The fly mass ceases to have any effect.  Finally, the stretching of the tip segment contributes elastic and damping forces.
        
        ## Thus, I implement holding this way:  Remove the original tip variables from $dynams.  Remove the fly mass, but treat the tip seg mass as a new fly mass, but keep its location in the (no longer dynamic) tip segment.  This affects the cartesian partials, which are modified explicitly. Internal and external velocities act on this cg.
        
=begin comment

         # Putting the above scheme in place:
        if ($holding == 0 and $Arg_holding == 1){           # Begin holding tip.
            Set_HeldTip($T0);
            $holding    = 1;
        } elsif ($holding == 1 and $Arg_holding == -1){     # Begin releasing tip.
            $holding = -1;
        } elsif ($holding == -1 and $Arg_holding == 0){     # Begin free tip.
            $holding = 0;
        }

=end comment

=cut
		
		# Must do this after setting held tip:
		$Dynams0        = $Arg_Dynams->copy;
		$numLineSegs	= $Dynams0->nelem/6 - $numRodSegs;
    }
    else {die "Unknown mode.\nStopped"}
	
	
	if ($mode eq "initialize" or $mode eq "restart_swing"){

		# Setup the shared storage:
		Init_WorkingCopies();
		Init_DynamSlices();
		Init_HelperPDLs();
		Init_HelperSlices();
		
		# Need do this just this once:
		Calc_CartesianPartials();    # Needs the helper PDLs and slices to be defined
		Calc_KE_Inverse();
	}

    if ($mode eq "initialize"){
        ## More initialization that needs to be done after the Init_'s above.
 
        #pq($Dynams0);
        
        if ($loadedStateIsEmpty){Set_ps_From_qDots($T0)}
        # This will load the $ps section of $dynams.
		
		if ($tipReleaseEndTime > $T0){Set_HeldTip($T0)}

        # Initialized dt moving average mechancism:
        #$init_verbose = $verbose;
        $DE_movingAvDt = DEAverageDt($dT0,20);
        if ($verbose>=3){pq($DE_movingAvDt)}
        $DE_lastSteppingCall = 0;
        $DE_lastSteppingT    = $T0;
        $DE_maxAttainedT    = $T0;

        # Figuring maybe 1*$nqs calls per step trial.
    }
	
    JACInit();

    $DE_status          = 0;
    $DE_errMsg          = "";

}

my $numSegs;
my ($handleLen,$rodSegKs,$rodSegCs);

sub Init_WorkingCopies {

	## Note that in the current implementation, the value of $holding has no effect on the working copies.  They are always what they would be if $holding were zero.
	
	# Force $holding to be zero just in this function.  Keep framework for if we ever implement hauling:
	my $holding = 0;
    
    PrintSeparator("Making working copies",4);
    
    if (DEBUG and $verbose>=4){pq($numRodSegs,$init_numLineSegs,$numLineSegs)}
    if (DEBUG and $verbose>=4){pq($stripping,$holding)}
 
    $numSegs    = $numRodSegs + $numLineSegs;

    my $iRods   = $numRodSegs ? sequence($numRodSegs) : zeros(0);
    my $iLines;
    if ($init_numLineSegs){
        if (!$stripping and !$holding){
            $iLines = $numRodSegs + sequence($numLineSegs);
        } elsif ($stripping) {
            my $numRemovedSegs = $init_numLineSegs-$numLineSegs;
            $iLines = ($numRodSegs+$init_numLineSegs-$numLineSegs) + sequence($numLineSegs);
        } elsif ($holding){ # OK for both 1 and -1; $numLineSegs was set appropriately in restart.
            $iLines = $numRodSegs + sequence($numLineSegs);
        } else {    # stripping and holding
           die "ERROR: For now, cast stripping (ie, hauling) is not implemented.\nStopped"
        }
        
    } else { $iLines = zeros(0)}
    #pq($iRods,$iLines);
    
    my $iKeeps  = $iRods->glue(0,$iLines);
    if (DEBUG and $verbose>=4){pq($init_segLens)}
    #pq($iRods,$iLines,$iKeeps);

    $segLens    = $init_segLens->dice($iKeeps)->copy;
    $segDiams	= $init_segDiams->dice($iKeeps)->copy;
    $segMasses	= $init_segMasses->dice($iKeeps)->copy;
    $segKs      = $init_segKs->dice($iKeeps)->copy;
    $segCs      = $init_segCs->dice($iKeeps)->copy;
    if (DEBUG and $verbose>=4){pq($segLens,$segDiams,$segMasses,$segKs,$segCs)}
    
    
    if (!$airOnly){
        $segVols   = $init_segVols->dice($iKeeps)->copy;
        if (DEBUG and $verbose>=4){pq($segVols)}
    }
 


    my $iiKeeps = $numRodSegs ? sequence($numRodSegs) : zeros(0);
    # WARNING:  New variable since dice should not make a copy of the indices until they go out of scope.
    #pq($iiKeeps);

    #$rodKsNoTip = $init_segKs->dice($iiKeeps);
    #$rodCsNoTip = $init_segCs->dice($iiKeeps);

    $rodSegLens = $segLens->dice($iiKeeps);
    
    if ($numRodSegs){
        $handleLen  = $rodLength - $actionLength;
        $rodSegKs   = $segKs(0:$numRodSegs-1);
        $rodSegCs   = $segCs(0:$numRodSegs-1);
    }
    
    
    #if (DEBUG and $verbose>=4){pq($rodKsNoTip,$rodCsNoTip)}

    my $iiiKeeps = $numLineSegs ? $numRodSegs + sequence($numLineSegs) : zeros(0);
    # WARNING:  New variable since dice should not make a copy of the indices until they go out of scope.
    #pq($iiiKeeps);
   
    $lineSegLens        = $segLens->dice($iiiKeeps);
    my $lineSegMasses	= $segMasses->dice($iiiKeeps);
    $lineSegKs          = $segKs->dice($iiiKeeps);
    $lineSegCs          = $segCs->dice($iiiKeeps);

    my $lineSegVols;
    if (!$airOnly){
        $lineSegVols    = $segVols->dice($iiiKeeps);
    }
    
    
    if (DEBUG and $verbose>=4){pq($rodSegLens,$lineSegLens)}

    # Make some copies to be fixed for this run:
    if ($stripping){   # For now, implies !$airOnly.
        $lineSeg0LenFixed       = $lineSegLens(0)->copy;
        $lineSeg0MassFixed		= $lineSegMasses(0)->copy;
        $lineSeg0VolFixed		= $lineSegVols(0)->copy;
        $lineSeg0KFixed         = $lineSegKs(0)->copy;
        $lineSeg0CFixed         = $lineSegCs(0)->copy;
    }
    
    if ($holding == 1){
        $HeldSegLen = $init_segLens(-1);
        $HeldSegK   = $init_segKs(-1);
        $HeldSegC   = $init_segCs(-1);
    }
    
    # Implement the conceit that when holding == 1 the last seg specs are attributed to the fly, and the calculation is done without the original last seg's dynamical variables.  Weights at all inertial nodes for use in Calc_pDotsGravity().  The contribution to the forces from gravity for the line is independent of the momentary configuration and so can be computed in advance here.
    $flyNomLen      = ($holding == 1) ? $init_segLens(-1) : $init_flyNomLen;
    $flyNomDiam     = ($holding == 1) ? $init_segDiams(-1) : $init_flyNomDiam;
    $flyMass		= ($holding == 1) ? $init_segMasses(-1) : $init_flyMass;
	
    if (!$airOnly){
        $flyDispVol        = ($holding == 1) ? $init_segVols(-1) : $init_flyDispVol;
        # For parallelism.  Actually there never will be tip holding when swinging.
    }
    
    $Masses		= $segMasses;
	
	$outboardMassSums	= cumusumover($Masses(-1:0));
	$outboardMassSums	= $outboardMassSums(-1:0);
	
	$outboardMassSumsFixed	= $outboardMassSums;
    if ($verbose>=3){pq($Masses,$outboardMassSums)}
        

    # Prepare "extended" lower tri matrix used in constructing dCGQs_dqs in Calc_CartesianPartials():
    #my $extraRow        = ($holding == 1) ? zeros($numSegs) : ones($numSegs);
    $lowerTri   = LowerTri($numSegs,1);
    if (DEBUG and $verbose>=5){pq($lowerTri)}
    # Extra row for fly weight.
        

    my $gravityForces    = -$nominalG*$surfaceGravityCmPerSec2*$Masses; # Dynes.
    if ($verbose>=3){pq($gravityForces)}
    
    
    if (!$airOnly){
        
        # No holding in sink implentation.
        my $submergedBuoyancyForces = $nominalG*$surfaceGravityCmPerSec2*$segVols*$waterDensity;
        if ($verbose>=3){pq($submergedBuoyancyForces)};
        
        my $submergedNetForces     = $nominalG + $submergedBuoyancyForces;
        if ($verbose>=2 and ($mode eq "initialize")){pq($submergedNetForces)};
    }
    
}
    

my $smallNumber     = 1e-8;
my $KSoftRelease    = 100; # Used only for soft release.


# Use the PDL slice mechanism in the integration loop to avoid as much copying as possible.  Except where reloaded (using .=); must be treated as read-only:

# Declare the dynamical variables and their useful slices:
my ($nSegs,$nRodSegs,$nLineSegs,$nQs,$nqs);

my $dynamDots;
my ($idx0,$idy0,$idz0);
my ($qs,$dxs,$dys,$dzs,$drs);
my ($ps,$dxps,$dyps,$dzps);
my ($qDots,$dxDots,$dyDots,$dzDots);    # Reloaded in Calc_qDots().
my ($pDots,$dxpDots,$dypDots,$dzpDots);                                      # Reloaded in Calc_pDots().
my ($rodDxs,$rodDys,$rodDzs,$lineDxs,$lineDys,$lineDzs);
my ($rodDxDots,$rodDyDots,$rodDzDots,$lineDxDots,$lineDyDots,$lineDzDots);

my ($iX0,$iY0,$iZ0);
my ($uXs,$uYs,$uZs);

my ($rodDrs,$uRodXs,$uRodYs,$uRodZs);                # Reloaded in Calc_dQs()
my ($lineDrs,$uLineXs,$uLineYs,$uLineZs);                # Reloaded in Calc_dQs()
my ($drDots,$rodDrDots,$lineDrDots);


sub Init_DynamSlices {
    
    ## Initialize counts, indices and useful slices of the dynamical variables.
    
    PrintSeparator ("Setting up the dynamical slices",4);
    if (DEBUG and $verbose>=4){pq($Dynams0)};
	
    $nSegs      = $numSegs;
    
    $iX0        = 0;
    $iY0        = $nSegs;
    $iZ0        = 2*$nSegs;
    $nQs        = 3*$nSegs;

    $nRodSegs   = $numRodSegs;
    
    #pq($numLineSegs);
    $nLineSegs = $numLineSegs;  # Nodes outboard of the rod tip node.  The cg for each of these is inboard of the node.  However, the last node also is the location of an extra quasi-segment that represents the mass of the fly.
    
    $nqs        = 3*$nSegs;
	
    if (DEBUG and $verbose>=4){pq($nRodSegs,$nLineSegs,$nSegs,$nQs,$nqs)}
    
    $dynams     = $Dynams0->copy->flat;    # Initialize our dynamical variables, reloaded at the beginning of DE().
    
    if ($dynams->nelem != 2*$nqs){die "ERROR: size mismatch with \$Dynams0.\nStopped"}

    $dynamDots  = zeros($dynams);   # Set as output of DE().

    $idx0       = 0;
    $idy0       = $idx0+$nSegs;
    $idz0       = $idy0+$nSegs;
    if (DEBUG and $verbose>=4){pq($idx0,$idy0,$idz0)}
    
    $qs         = $dynams(0:$nqs-1);
    if (DEBUG and $verbose>=3){pq($dynams,$qs)}
    
    $dxs        = $qs(0:$idy0-1);
    $dys        = $qs($idy0:$idz0-1);
    $dzs        = $qs($idz0:-1);
    
    # Avoid slice trap if $nRodSegs == 0:
    $rodDxs     = ($nRodSegs)?$dxs(0:$nRodSegs-1):zeros(0);
    $rodDys     = ($nRodSegs)?$dys(0:$nRodSegs-1):zeros(0);
    $rodDzs     = ($nRodSegs)?$dzs(0:$nRodSegs-1):zeros(0);
    
    $lineDxs    = $dxs($nRodSegs:-1);
    $lineDys    = $dys($nRodSegs:-1);
    $lineDzs    = $dzs($nRodSegs:-1);
    
    $ps         = $dynams($nqs:-1);
    if (DEBUG and $verbose>=4){pq($ps)}
    
    $dxps       = $ps(0:$idy0-1);
    $dyps       = $ps($idy0:$idz0-1);
    $dzps       = $ps($idz0:-1);
 
    $qDots      = $ps->copy;
        # Correctly initialized for mode="initialize" and empty loaded state, unused otherwise until reloaded in Calc_qDots().
    
    $dxDots     = $qDots(0:$idy0-1);
    $dyDots     = $qDots($idy0:$idz0-1);
    $dzDots     = $qDots($idz0:-1);
    
    $rodDxDots  = ($nRodSegs)?$dxDots(0:$nRodSegs-1):zeros(0);
    $rodDyDots  = ($nRodSegs)?$dyDots(0:$nRodSegs-1):zeros(0);
    $rodDzDots  = ($nRodSegs)?$dzDots(0:$nRodSegs-1):zeros(0);
    
    $lineDxDots = $dxDots($nRodSegs:-1);
    $lineDyDots = $dyDots($nRodSegs:-1);
    $lineDzDots = $dzDots($nRodSegs:-1);

    
    ($drs,$uXs,$uYs,$uZs) = map {zeros($nSegs)} (0..3);
    
    $rodDrs     = ($nRodSegs)?$drs(0:$nRodSegs-1):zeros(0);
    $uRodXs     = ($nRodSegs)?$uXs(0:$nRodSegs-1):zeros(0);
    $uRodYs     = ($nRodSegs)?$uYs(0:$nRodSegs-1):zeros(0);
    $uRodZs     = ($nRodSegs)?$uZs(0:$nRodSegs-1):zeros(0);
   
    
    $lineDrs    = $drs($nRodSegs:-1);
    $uLineXs    = $uXs($nRodSegs:-1);
    $uLineYs    = $uYs($nRodSegs:-1);
    $uLineZs    = $uZs($nRodSegs:-1);
    
    $drDots     = zeros($nSegs);
    $rodDrDots  = ($nRodSegs)?$drDots(0:$nRodSegs-1):zeros(0);
    $lineDrDots = $drDots($nRodSegs:-1);
    
    $pDots  = zeros($ps);
    
    $dxpDots     = $pDots(0:$idy0-1);
    $dypDots     = $pDots($idy0:$idz0-1);
    $dzpDots     = $pDots($idz0:-1);
    
    
    
}


my ($dWs_dws);
my $extQDots;
my ($QDots,$dragForces,$netAppliedForces);



sub Init_HelperPDLs {
    
    ## Initialize pdls that will be referenced by slices.
    
    PrintSeparator("Initializing helper PDLs",5);
	
    # Storage for the nodes partials:
    $dWs_dws		= zeros($nSegs,$nSegs);
   
    # WARNING and FEATURE:  dummy acts like slice, and changes when the original does!  I make use of this in AdjustFirstSeg_STRIPPING().
    $MassesDummy1	= $Masses->dummy(1,$nSegs);
    
    # Storage for the cgs partials:
    $extQDots		= zeros($nQs);
    
    $QDots			= zeros($nQs);
    $dragForces		= zeros($nQs);
	
	$netAppliedForces = zeros($nQs);
}



my ($VXs,$VYs,$VZs,
	$netAppliedXs,$netAppliedYs,$netAppliedZs,
	$rodVXs,$rodVYs,$rodVZs,
	$lineVXs,$lineVYs,$lineVZs,
	$dragXs,$dragYs,$dragZs,
	$rodDragXs,$rodDragYs,$rodDragZs,
	$lineDragXs,$lineDragYs,$lineDragZs);

sub Init_HelperSlices {
    
    PrintSeparator("Initializing helper slices",5);
	
	$VXs		= $QDots(0:$nSegs-1);
    $VYs		= $QDots($nSegs:2*$nSegs-1);
    $VZs		= $QDots(2*$nSegs:-1);
    
    $rodVXs     = ($nRodSegs)?$VXs(0:$nRodSegs-1):zeros(0);
    $rodVYs     = ($nRodSegs)?$VYs(0:$nRodSegs-1):zeros(0);
    $rodVZs     = ($nRodSegs)?$VZs(0:$nRodSegs-1):zeros(0);

    $lineVXs    = $VXs($nRodSegs:-1);
    $lineVYs    = $VYs($nRodSegs:-1);
    $lineVZs    = $VZs($nRodSegs:-1);
	
	$dragXs		= $dragForces(0:$nSegs-1);
    $dragYs		= $dragForces($nSegs:2*$nSegs-1);
    $dragZs		= $dragForces(2*$nSegs:-1);
    
    $rodDragXs	= ($nRodSegs)?$dragXs(0:$nRodSegs-1):zeros(0);
    $rodDragYs	= ($nRodSegs)?$dragYs(0:$nRodSegs-1):zeros(0);
    $rodDragZs	= ($nRodSegs)?$dragZs(0:$nRodSegs-1):zeros(0);

    $lineDragXs	= $dragXs($nRodSegs:-1);
    $lineDragYs	= $dragYs($nRodSegs:-1);
    $lineDragZs	= $dragZs($nRodSegs:-1);
	
	$netAppliedXs =	$netAppliedForces(0:$nSegs-1);
	$netAppliedYs =	$netAppliedForces($nSegs:2*$nSegs-1);
	$netAppliedZs =	$netAppliedForces(2*$nSegs:-1);
	
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



# DYNAMIC VARIABLE HANDLING ===========================================================

sub Unpack_qs {     # Safe version, with ->copy
    my ($qs) = @_;
    
    
    my ($dxs,$dys,$dzs) = map {zeros(0)} (0..4);
    
    $dxs     = $qs(0:$idy0-1)->copy;
    $dys     = $qs($idy0:$idz0-1)->copy;
    $dzs     = $qs($idz0:-1)->copy;
   
    return ($dxs,$dys,$dzs);
}



# COMPUTING DYNAMIC DERIVATIVES ===========================================================

my $stripCutoffMult = 0.001;
	# Make the actual cutoff relative to the unstripped length

sub AdjustFirstSeg_STRIPPING { use constant V_AdjustFirstSeg_STRIPPING => 0;
    my ($t) = @_;
    
    #pq($segLens,$lineSegLens,$segMasses,$Masses,$outboardMassSums,$Vols);
    
    my $thisSegStripStartTime =
		($stripStartTime>$thisSegStartT) ? $stripStartTime : $thisSegStartT;

	#pq($lineSeg0LenFixed,$t,$thisSegStartT,$stripRate,$thisSegStripStartTime);
	my $deltaT = $t-$thisSegStripStartTime;
	#if ($deltaT < 0){return}		### if nothing, then kink in ftn! and time gets reduced!!!
	#pq($deltaT);
	
    my $stripNomLen = $lineSeg0LenFixed - $deltaT*$stripRate;
	#pq($stripNomLen);
	
	
    #if ($stripNomLen < $stripCutoff){$stripNomLen = $stripCutoff}
	my $stripCutoff = $lineSeg0LenFixed * $stripCutoffMult;
    if ($stripNomLen < $stripCutoff){
		# Don't make any more changes in this seg. Just like on stripping onset, waste a few stepper calls to get things into the new situation:
		$stripping = 0;
		return;
	}

    if (DEBUG and V_AdjustFirstSeg_STRIPPING and $verbose>=5){pq($lineSeg0LenFixed,$stripNomLen)}
    
    #if ($stripNomLen < $stripCutoff){return 0}
    
    #$segLens(0)         .= $stripNomLen;
    $lineSegLens(0)     .= $stripNomLen;
        # This is a slice of $segLens, so 2-way adjustment takes care of that too.
    
    my $stripFract      = $stripNomLen/$lineSeg0LenFixed;

    my $stripMass		= $lineSeg0MassFixed * $stripFract;
    #my $stripMass		= $line0SegMassFixed * $stripFract;
    $segMasses(0)		.= $stripMass;
    # At least approximately right.
    $Masses(0)			.= $stripMass;
    $outboardMassSums
		.= ($stripMass-$lineSeg0MassFixed)+$outboardMassSumsFixed;
	
    
    #$segDiams($idx0)      .= ??      For now, leave this unchanged.
    my $stripVol   = $lineSeg0VolFixed(0) * $stripFract;
    $segVols($idx0) .= $stripVol;
    
    # The original Ks and Cs include segLen in the denominator.
    $lineSegKs(0)       .= $lineSeg0KFixed / $stripFract;
    $lineSegCs(0)       .= $lineSeg0CFixed / $stripFract;
    if (DEBUG and V_AdjustFirstSeg_STRIPPING and $verbose>=5){pq($lineSegKs,$lineSegCs)}
    
    # For now, will leave cg unchanged.
    if (DEBUG and V_AdjustFirstSeg_STRIPPING and $verbose>=5){pq($stripMass,$stripVol)}
    #pq($segLens,$lineSegLens,$segMasses,$Masses,$QMasses,$segVols);
    
}



sub AdjustTrack_STRIPPING { use constant V_AdjustTrack_STRIPPING => 0;
    my ($t) = @_;
    
    ### Doesn't seem to be necessary since $stripCutoff = 0.001;    # Cm. works in preliminary tests.  Cutoff = 0, however, blows up, as expected.
}


sub Calc_dQs { use constant V_Calc_dQs => 1;
    # Pre-reqs: $qs set, and if $numRodSegs, Calc_Driver().
    
    ## Calculate the rod and line segments as cartesian vectors from the dynamical variables.  In this formulation, there is not much to do, since the $dXs = $dxs, etc, so only the $drs are loaded here, and the cartesian unit vectors.

    if (DEBUG and V_Calc_dQs and $verbose>=4){print "\nCalc_dQs ----\n"}
	#pq($dxs,$dys,$dzs);
	
    $drs  .= sqrt($dxs**2 + $dys**2 + $dzs**2);
    # Line dxs, dys were automatically updated when qs was loaded.
    
    # Compute X and Y components of the outboard pointing unit vectors along the segments:
    $uXs .= $dxs/$drs;
    $uYs .= $dys/$drs;
    $uZs .= $dzs/$drs;

    # convert any nan's to zeros.
    my $ii = which(!$drs);
    if (!$ii->isempty){
        $uXs($ii) .= 0;
        $uYs($ii) .= 0;
        $uZs($ii) .= 0;
    }
    
    if (DEBUG and V_Calc_dQs and $verbose>=4){pq($drs)}
    if (DEBUG and V_Calc_dQs and $verbose>=5){pq($uXs,$uYs,$uZs)}
}

my ($driverX,$driverY,$driverZ,$driverDX,$driverDY,$driverDZ);
my ($driverXDot,$driverYDot,$driverZDot,$driverDXDot,$driverDYDot,$driverDZDot);


sub Calc_Driver { use constant V_Calc_Driver => 1;
    my ($t,$print) = @_;   # $t is a PERL scalar.
	
    my $inTime = $t;
	$print = (defined($print) and !$print)?0:1;
	
    if ($t < $driverStartTime) {$t = $driverStartTime}
    if ($t > $driverEndTime) {$t = $driverEndTime}
    
    
    #($driverDX,$driverDY,$driverDZ) = map {0} (0..2);
    
    $driverX        = $driverXSpline->evaluate($t);
    $driverY        = $driverYSpline->evaluate($t);
    $driverZ        = $driverZSpline->evaluate($t);
	
	#if (DEBUG and V_Calc_Driver and $verbose>=3){pq($driverX,$driverY,$driverZ)}
    
    if ($numRodSegs){	# There is a handle
	
		## NOTE that my driver handle direction vectors are always UNIT length.  That is all I ever need in my calculations.

        $driverDX       = $driverDXSpline->evaluate($t);
        $driverDY       = $driverDYSpline->evaluate($t);
        $driverDZ       = $driverDZSpline->evaluate($t);
        
        # Enforce exact handle UNIT length constraint:
        my $len = sqrt($driverDX**2+$driverDY**2+$driverDZ**2);
        $driverDX   /= $len;
        $driverDY   /= $len;
        $driverDZ   /= $len;
		
		#if (DEBUG and V_Calc_Driver and $verbose>=3){pq($driverDX,$driverDY,$driverDZ)}
	}
    
    
    # Critical to make sure that the velocity is zero if outside the drive time range:
    ($driverXDot,$driverYDot,$driverZDot) = map {0} (0..2);
    if ($numRodSegs){
        ($driverDXDot,$driverDYDot,$driverDZDot) = map {0} (0..2);
    }
    
    if ($t > $driverStartTime and $t < $driverEndTime){
        
        my $dt = ($t <= ($driverStartTime+$driverEndTime)/2) ? 0.001 : -0.001;
        $dt *= $driverEndTime - $driverStartTime;     # Must be small compared to changes in the splines.
		
		# Abusing notation:
        $driverXDot = $driverXSpline->evaluate($t+$dt);
        $driverXDot = ($driverXDot-$driverX)/$dt;
        
        $driverYDot = $driverYSpline->evaluate($t+$dt);
        $driverYDot = ($driverYDot-$driverY)/$dt;
        
        $driverZDot = $driverZSpline->evaluate($t+$dt);
        $driverZDot = ($driverZDot-$driverZ)/$dt;
		
		if ($numRodSegs and $verbose>=3){
			# Handle dots are only used for reporting.
			
			# And again abusing:
			$driverDXDot = $driverDXSpline->evaluate($t+$dt);
			$driverDYDot = $driverDYSpline->evaluate($t+$dt);
			$driverDZDot = $driverDZSpline->evaluate($t+$dt);
			
			my $len = sqrt($driverDXDot**2+$driverDYDot**2+$driverDZDot**2);
			$driverDXDot   /= $len;
			$driverDYDot   /= $len;
			$driverDZDot   /= $len;
			
			$driverDXDot = ($driverDXDot-$driverDX)/$dt;
			$driverDYDot = ($driverDYDot-$driverDY)/$dt;
			$driverDZDot = ($driverDZDot-$driverDZ)/$dt;
		}
		
		#if (DEBUG and V_Calc_Driver and $verbose>=3){pq($driverXDot,$driverYDot,$driverZDot)}
    }

    if (DEBUG and $print and V_Calc_Driver and $verbose>=3){
        printf("driver=(%.4f,%.4f,%.4f); driverDot=(%.4f,%.4f,%.4f)\n",$driverX,$driverY,$driverZ,$driverXDot,$driverYDot,$driverZDot);
        if ($numRodSegs){printf("driverDir=(%.4f,%.4f,%.4f)\n",$driverDX,$driverDY,$driverDZ)}
        #if ($numRodSegs){printf("driverDir=(%.4f,%.4f,%.4f); driverDirDot=(%.4f,%.4f,%.4f)\n",$driverDX,$driverDY,$driverDZ,$driverDXDot,$driverDYDot,$driverDZDot);
    }
	
    # Return values (but not derivatives) are used only in the calling program:
    return ($driverX,$driverY,$driverZ,$driverDX,$driverDY,$driverDZ);
}


my ($Xs,$Ys,$Zs);

# Used only in computing fluid drag, not for plotting, so returns only coordinates for the active nodes.  That is excluding handle top and bottom nodes.
sub Calc_Qs { use constant V_Calc_Qs => 0;
    # Pre-reqs:  Calc_Driver() and Calc_dQs().
    
    ## Compute the cartesian coordinates Xs, Ys and Zs of all the seg and fly CGs.
    if (DEBUG and V_Calc_Qs and $verbose>=5){print "\nCalc_Qs --- \n"}
    
    my $dxs = pdl($driverX)->glue(0,$dxs);
    my $dys = pdl($driverY)->glue(0,$dys);
    my $dzs = pdl($driverZ)->glue(0,$dzs);
    
    $Xs = cumusumover($dxs);
    $Ys = cumusumover($dys);
    $Zs = cumusumover($dzs);
	
	$Xs = $Xs(1:-1);
	$Ys = $Ys(1:-1);
	$Zs = $Zs(1:-1);
	
    if (DEBUG and V_Calc_Qs and $verbose>=5){pq($Xs,$Ys,$Zs)}
    #return ($Xs,$Ys,$Zs);
}



sub Calc_CartesianPartials { use constant V_Calc_CartesianPartials => 0;
    # Pre-reqs: $qs set.

    if (DEBUG and V_Calc_CartesianPartials and $verbose>=4){print "\nCalc_CartesianPartials ---- \n"}
	
	## In computing momenta and momentum changes, indeed for many things, need work only one space dimension at a time.

    ## With the current set of dynamical variables, the partials are constant during the integration, so this need only be called once during init.
    
    ## Compute first partials of the nodal cartesian coordinates with respect to the dynamical variables.  NOTE that the second partials are not needed in this case.
	
	## I use the dynamical variable w to stand for x, y, or z, and similarly W to stand for the actual cartesian variables X, Y, or Z.
    
    $dWs_dws .= $lowerTri;
    #pq($dWs_dws);
	
    if (DEBUG and V_Calc_CartesianPartials and $verbose>=5){print "In calc partials: ";pq($dWs_dws)}

    #return ($dWs_dws);
}


=begin comment

sub Calc_ExtQDots { use constant V_Calc_ExtQDots => 0;
    # Pre-reqs:  Calc_Driver(), and if $numRodSegs, Calc_CartesianPartials().
    
    ## External velocity is nodal motion induced by driver motion, path and orientation, but not by the bending at the zero node.  NOTE that the part of the external V's contributed by the change in driver direction is gotten from the first column of the dQs_dqs matrix (which is the same as the first column of the $dQs_dthetas matrix), in just the same way that the internal contribution of the bending of the 0 node is.
    
    if (DEBUG and V_Calc_ExtQDots and $verbose>=4){print "\nCalc_ExtQDots ----\n"}
	
    $extQDots .= (   $driverXDot*ones($nSegs))
                    ->glue(0,$driverYDot*ones($nSegs))
                    ->glue(0,$driverZDot*ones($nSegs));
    
    #return $extQDots;
}

=end comment

=cut

my $dMWs_dws_Tr;
my ($fwdKE,$invKE);

sub Calc_KE_Inverse { use constant V_Calc_KE_Inverse => 1;
    # Pre-reqs:  $ps set, Calc_CartesianPartials() or Calc_CartesianPartials_NoRodSegs().  If not$numRodSegs, this need be called only once, during init.
    
    ## Solve for qDots in terms of ps from the definition of the conjugate momenta as the partial derivatives of the kinetic energy with respect to qDots.  We evaluate the matrix equation      qDots = ((Dtr*bigM*D)inv)*(ps - Dtr*bigM*Vext).
    
    # !!!  By definition, p = ∂/∂qDot (Lagranian) = ∂/∂qDot (KE) - 0 = ∂/∂qDot (KE).  Thus, this calculation is not affected by the definition of the Hamiltonian as Hamiltonian = p*qDot - Lagrangian, which comes later.  However, the pure mathematics of the Legendre transformation then gives qDot = ∂/∂p (H).
 
    ## When using the offset model, $invKE need be computed only once!!!!!
    
    if (DEBUG and V_Calc_KE_Inverse and $verbose>=4){print "\nCalc_KE_Inverse ---- \n"}
	
	# To keep from having avoidably small determinants for fwd and inv, scale the masses:
	
	## In computing momenta and momentum changes, need work only one space dimension at a time.
	
	
    $dMWs_dws_Tr = $MassesDummy1*($dWs_dws->transpose);
    if (DEBUG and V_Calc_KE_Inverse and $verbose>=5){pq $dMWs_dws_Tr}


    $fwdKE = $dMWs_dws_Tr x $dWs_dws;
    if (DEBUG and V_Calc_KE_Inverse and $verbose>=5){pq $fwdKE}
	
	my $nelem	= $fwdKE->nelem;
	my $avElem	= sum(abs($fwdKE))/$nelem;
	my $adjFwd	= $fwdKE/$avElem;
	
	my $adjFwdDet;
	if (DEBUG and V_Calc_KE_Inverse and $verbose>=4){
		pq($nelem,$avElem);
		$adjFwdDet = det($adjFwd);
		pq($adjFwdDet);
	}
	
    my $adjInv = $adjFwd->inv;
	if (DEBUG and V_Calc_KE_Inverse and $verbose>=5){pq($adjInv)}
		
	if (DEBUG and V_Calc_KE_Inverse and $verbose>=4){
		my $adjInvDet = det($adjInv);
		pq($adjInvDet);

		my $adjMatPdt = $adjInv x $adjFwd;
		if ($verbose>=5){pq($adjMatPdt)}

		my $adjDetPdt = $adjFwdDet * $adjInvDet;
		pq($adjDetPdt);
	
		my $adjMatPdtErr = max(abs($adjMatPdt - identity(sqrt($nelem))));
		pq($adjMatPdtErr);
	}
	
	$invKE = $adjInv/$avElem;
	
	my $matPdt		= $invKE x $fwdKE;
	my $matPdtErr	= abs(max($matPdt - identity(sqrt($nelem))));
	if ($matPdtErr >= $smallNum){
		
		warn "WARNING:  Was not able to get good inverse.  Make sure all segment lengths and weights are significantly greater than zero.\n";
	}
	if ($verbose>=3){pq($matPdtErr)}

   # return($dMWs_dws_Tr,$invKE);
}



sub Set_ps_From_qDots {
    my ($t) = @_;
	
	## Use the definition of the conjugate variables. See also Calc_qDots().
	
    PrintSeparator("Initialize ps from qDots",4);
    if (DEBUG and $verbose>=4){pq($qDots)}
    
    # Requires that $qDots have been set:
    Calc_Driver($t);
	
	$dxps .= ($fwdKE x $dxDots->transpose)->flat + $driverXDot*$outboardMassSums;
	$dyps .= ($fwdKE x $dyDots->transpose)->flat + $driverYDot*$outboardMassSums;
	$dzps .= ($fwdKE x $dzDots->transpose)->flat + $driverZDot*$outboardMassSums;
	
    if (DEBUG and $verbose>=4){pq($ps)}
    #    return $ps;
}


sub Calc_qDots { use constant V_Calc_qDots => 1;
    # Pre-reqs:  $ps set. Calc_KE_Inverse() need be called only once, during init.

    if (DEBUG and V_Calc_qDots and $verbose>=4){print "\nCalc_qDots ----\n"}
	
	# Using cartesian offset dynamical variables, the direction components are independent.  Also, the generalized momentum for each node is the sum of the cartesian momenta for that node and all outboard nodes.  These generalized momenta do depend on the external (driving velocity), but only up to a mass-sum constant and the velocity.
	
	my $int_dwps = $dxps - $driverXDot*$outboardMassSums;
	$dxDots	.= ($invKE x $int_dwps->transpose)->flat;
	
	$int_dwps = $dyps - $driverYDot*$outboardMassSums;
	$dyDots	.= ($invKE x $int_dwps->transpose)->flat;
	
	$int_dwps = $dzps - $driverZDot*$outboardMassSums;
	$dzDots	.= ($invKE x $int_dwps->transpose)->flat;
	
	
    $drDots .= (1/$drs)*($dxs*$dxDots+$dys*$dyDots+$dzs*$dzDots);   # 0.5*2=1.
    if (DEBUG and V_Calc_qDots and $verbose>=4){pq($dxDots,$dyDots,$dzDots,$drDots)}
    
    # return $qDots;
}




sub Calc_QDots { use constant V_Calc_QDots => 1;
    # Pre-reqs:  Calc_CartesianPartials() and Calc_qDots().
    
    if (DEBUG and V_Calc_QDots and $verbose>=4){print "\nCalc_QDots ----\n"}

    my $intWDots	= ($dWs_dws x $dxDots->transpose)->flat;
	$VXs			.= $intWDots + $driverXDot;
	
    $intWDots		= ($dWs_dws x $dyDots->transpose)->flat;
	$VYs			.= $intWDots + $driverYDot;
	
    $intWDots		= ($dWs_dws x $dzDots->transpose)->flat;
	$VZs			.= $intWDots + $driverZDot;
	
    # return $QDots;
}




my ($pDotsRodXs,$pDotsRodYs,$pDotsRodZs);
my $smallAngle = 0.001;		# Radians.
my ($rodStretchDampingPowers,$rodBendDampingPowers);
my ($handleBendingForceX,$handleBendingForceY,$handleBendingForceZ); 	# For reporting.


sub Calc_pDotsRodMaterial { use constant V_Calc_pDotsRodMaterial => 1;
    
	
	## The code here implements our model where the rod is is composed of entensible/compressible but not bendable segments which are connected sequentially at their ends by springs that perfectly obey Hook's law with respect to bend angle.  This is entirely consonant with our system of dynamical variables that are the cartesian offsets specifying the segments.
	
	## This is obviously not the same as the real-world rod which bends in a smoothly varying arc, but in the limit of short segment lengths the two converge.
	
	## An important question is how best to relate the elastic and damping properties of the real rod material to effective spring and damping constants that come into play here.  See RCast3D::SetupModel() for what I actually did.  There is additional theoretical discussion in the section FORCES AND CONJUGATE MOMENTA in the POD at the end of this file.  Note, in particular, the point about the difference between fiber-against-fiber friction and internal fiber friction.
	
	## 9/15/2019 - Finally figured out the right understanding of hamilton in this context, where the rod dynamical variables are just cartesian differences.
	
	
    if (DEBUG and V_Calc_pDotsRodMaterial and $verbose>=4){print "\nCalc_pDotsRodMaterial ----\n"}

    # Stretching is just Hook's law:
    my $stretches   = $rodDrs-$rodSegLens;
    my $stretchDots =
        $uRodXs*$rodDxDots+$uRodYs*$rodDyDots+$uRodZs*$rodDzDots;

    my $stretchForces	=    -$stretches*$rodSegKs;
    my $stretchDamps	=    -$stretchDots*$rodSegCs;
		# These are the stretch K's and C's, based on just the section areas.
	
    if ($verbose>=3){
		my $strains = $stretches/$rodSegLens;

		ppf("\$rodStrains    =\t","%8.7f\t",$strains);
		ppf("\$stretches     =\t","%8.7f\t",$stretches);
		ppf("\$stretchForces =\t","%8.0f\t",$stretchForces,"\n\n");
		
		ppf("\$stretchDots   =\t","%8.5f\t",$stretchDots);
		ppf("\$stretchDamps  =\t","%8.0f\t",$stretchDamps,"\n\n");
		
		$rodStretchDampingPowers = $stretchDamps * $stretchDots;
		if ($verbose>=4){ppf("\$stretchDampPows =\t","%7.0f\t",$rodStretchDampingPowers,"\n\n")}

	}
    #pq($uRodXs,$uRodYs,$uRodZs);
	
	my $stretchNetForces = $stretchForces + $stretchDamps;
	
	$pDotsRodXs = $stretchNetForces*$uRodXs;
    $pDotsRodYs = $stretchNetForces*$uRodYs;
    $pDotsRodZs = $stretchNetForces*$uRodZs;

 
	# The key thing to know about bending is that a change to one of the dynamical variables causes angle (and thus energy) changes at BOTH endpoints of the segment associated with that variable.
	
    # Bending force is Hook's law, but applied to the 3D angle at the segment junctions (expanded to include the junction between the handle and the rod active lowest segment, but not that between the tip rod segment and the inboard line segment).  The K's and C's here are based on the section 2nd moments.  Their products with the angle yield torques, and these must be resolved into forces by the specification of the proper lever arm.
	
#	my $uHandleDX = $driverDX/$handleLen;
#    my $uHandleDY = $driverDY/$handleLen;
#    my $uHandleDZ = $driverDZ/$handleLen;
	
	# To simplify (and symmetrize) the following formulas, I prepend the handle segment unit, and postpend a (fake) first line segment (which I take to be a copy of the last rod segment:
	my $uEXs	= pdl($driverDX)->glue(0,$uRodXs)->glue(0,$uRodXs(-1));
	my $uEYs	= pdl($driverDY)->glue(0,$uRodYs)->glue(0,$uRodYs(-1));
	my $uEZs	= pdl($driverDZ)->glue(0,$uRodZs)->glue(0,$uRodZs(-1));
#pq($uEXs,$uEYs,$uEZs);
	
	
	# For each interior joint (including that between the handle and the first active rod segment, and the joint between the last rod segment and the fake first line segment, figure the normal to the segment just above (upper) that lies in the plane of the joint and points toward the convex side of the joint angle.  These define the directions of HALF the full complement of restoring forces:
	my $projs	=	$uEXs(0:-2)*$uEXs(1:-1) +
					$uEYs(0:-2)*$uEYs(1:-1) +
					$uEZs(0:-2)*$uEZs(1:-1);
#if($verbose>=3){pq($projs)}

	# These normals point toward straightening, so they point in the same direction as the acceleration.
	my $upperXs	= $uEXs(0:-2) - $projs*$uEXs(1:-1);
	my $upperYs	= $uEYs(0:-2) - $projs*$uEYs(1:-1);
	my $upperZs	= $uEZs(0:-2) - $projs*$uEZs(1:-1);
#if($verbose>=3){pq($upperXs,$upperYs,$upperZs)}
	
	my $upperLens	= sqrt($upperXs**2 + $upperYs**2 + $upperZs**2);
	my $angles		= asin($upperLens);  # Always positive.
		# Includes the zero angle to the fake line segment.

	my $kTorques		= ($rodBendTorqueKs->glue(0,pdl(0)))*$angles;
		# Includes a zero torque at the rod tip.
	
	# Make the normals unit length:
	$upperXs /= $upperLens;
	$upperYs /= $upperLens;
	$upperZs /= $upperLens;
	
	my $ii = which(!$upperLens);
	if (!$ii->isempty){
		$upperXs($ii) .= 0;
		$upperYs($ii) .= 0;
		$upperZs($ii) .= 0;
	}

	# Similarly, for each interior joint, figure the normal to the segment just below (lower) that lies in the plane of the joint.  These a associated with the other half of the complement of restoring forces:
	my $lowerXs	= -$uEXs(1:-1) + $projs*$uEXs(0:-2);
	my $lowerYs	= -$uEYs(1:-1) + $projs*$uEYs(0:-2);
	my $lowerZs	= -$uEZs(1:-1) + $projs*$uEZs(0:-2);
	#if($verbose>=3){pq($lowerXs,$lowerYs,$lowerZs)}
	
	my $lowerLens	= sqrt($lowerXs**2 + $lowerYs**2 + $lowerZs**2);

	# Make the normals unit length:
	$lowerXs /= $lowerLens;
	$lowerYs /= $lowerLens;
	$lowerZs /= $lowerLens;
	
	$ii = which(!$lowerLens);
	if (!$ii->isempty){
		$lowerXs($ii) .= 0;
		$lowerYs($ii) .= 0;
		$lowerZs($ii) .= 0;
	}

	# Obtain the generalized forces for the segment dynamical variables.  NOTE that this is  definitely not Hook's Law for the deflection angles!!  This is because our dynamical variables are the cartesian segment length components, not the angles. Note that there is one more interior joint than there are DYNAMICAL segments and there is one more segment length than there are interior joints!

	# It is a tiny bit more correct to use $rodDrs rather that $rodSegLens, but since the rod is very resistant to stretch, the difference is 2nd order:
	my $bendGenForceXs =
		($upperXs(0:-2)*$kTorques(0:-2) - $lowerXs(1:-1)*$kTorques(1:-1))/$rodDrs;
	my $bendGenForceYs =
		($upperYs(0:-2)*$kTorques(0:-2) - $lowerYs(1:-1)*$kTorques(1:-1))/$rodDrs;
	my $bendGenForceZs =
		($upperZs(0:-2)*$kTorques(0:-2) - $lowerZs(1:-1)*$kTorques(1:-1))/$rodDrs;
	
	if ($verbose>=3){
		# For reporting, need the bending torque at the junction between the handle and the first active segment.  I believe this is:
		$handleBendingForceX = $lowerXs(0)*$kTorques(0);
		$handleBendingForceY = $lowerYs(0)*$kTorques(0);
		$handleBendingForceZ = $lowerZs(0)*$kTorques(0);
	}
		
	# Apply the appropriate lever arm:
	$bendGenForceXs /= $rodSegLens;
	$bendGenForceYs /= $rodSegLens;
	$bendGenForceZs /= $rodSegLens;
	
	if ($verbose>=3){
		my $bendDegs	= $angles(0:-2)*180/$pi;
		my $bendTorques	= $kTorques(0:-2);
		my $bendGenForces	=
			sqrt($bendGenForceXs**2 + $bendGenForceYs**2 + $bendGenForceZs**2);

		ppf("\$bendDegs       =\t","%7.3f\t",$bendDegs);
		ppf("\$bendGenForces  =\t","%7.0f\t",$bendGenForces,"\n\n");
		if ($verbose>=4){
			ppf("\$bendGenForceXs =\t","%7.0f\t",$bendGenForceXs);
			ppf("\$bendGenForceYs =\t","%7.0f\t",$bendGenForceYs);
			ppf("\$bendGenForceZs =\t","%7.0f\t",$bendGenForceZs,"\n\n");
		}
	}
	
	# Increment pDots:
	$pDotsRodXs += $bendGenForceXs;
	$pDotsRodYs += $bendGenForceYs;
	$pDotsRodZs += $bendGenForceZs;


	## As for bending damping, I suppose that internal friction due to rod fibers sliding over one another resolves to the model where at each joint there is a velocity-dependent spherically symmetric friction apparatus that resists changes in joint configuration, and that these frictional forces convert to generalized forces that contribute to the pDots.  As with the bending force, virtual changes in one of the rod dynamical variables (leaving all the others unchanged) lead to a frictional contribution from  the joints at BOTH ends of each rod segment:

	# For each rod segment project the segment velocity into the plane normal to the segment:
	my $projNs = $uRodXs*$rodDxDots+$uRodYs*$rodDyDots+$uRodZs*$rodDzDots;

	my $upperVXs	= $rodDxDots - $projNs*$uRodXs;
	my $upperVYs	= $rodDyDots - $projNs*$uRodYs;
	my $upperVZs	= $rodDzDots - $projNs*$uRodZs;

	my $cTorques	= $rodBendTorqueCs->glue(0,pdl(0));
	my $dampTorques	= ($cTorques(0:-2)+$cTorques(1:-1))/$rodDrs;
		# A normal velocity at the upper end of a segment gives rise to a frictional contribution from the joint at the lower end, but also implies an opposite velocity at the other (lower) end which gives rise to a frictional contribution from the joint at the upper end.  However, this second contribution must be applied to the implied virtual displacement at the lower end, and the product of the negative signs from the lower virtual velocity and lower virtual displacements yield the plus sign in the above formula.
	

	# Force opposes velocity:
	my $bendGenDampXs = -$upperVXs*$dampTorques/$rodSegLens;
	my $bendGenDampYs = -$upperVYs*$dampTorques/$rodSegLens;
	my $bendGenDampZs = -$upperVZs*$dampTorques/$rodSegLens;
	
	if ($verbose>=3){
		my $bendDampSpeeds	= sqrt($upperVXs**2+$upperVYs**2+$upperVZs**2);
		my $bendGenDamps =
			sqrt($bendGenDampXs**2 + $bendGenDampYs**2 + $bendGenDampZs**2);
		$rodBendDampingPowers = -$bendDampSpeeds*$bendGenDamps;

		ppf("\$bendDampSpeeds =\t","%7.1f\t",$bendDampSpeeds);
		ppf("\$bendGenDamps   =\t","%7.0f\t",$bendGenDamps,"\n\n");
		if ($verbose>=4){
			ppf("\$bendGenDampXs  =\t","%7.0f\t",$bendGenDampXs);
			ppf("\$bendGenDampYs  =\t","%7.0f\t",$bendGenDampYs);
			ppf("\$bendGenDampZs  =\t","%7.0f\t",$bendGenDampZs,"\n\n");
			
				### THIS NEEDS CHECKING !!!
			ppf("\$bendDampPows   =\t","%7.0f\t",$rodBendDampingPowers,"\n\n");
		}
	}
	
	# Increment pDots:
	$pDotsRodXs += $bendGenDampXs;
	$pDotsRodYs += $bendGenDampYs;
	$pDotsRodZs += $bendGenDampZs;

    if (DEBUG and V_Calc_pDotsRodMaterial and $verbose>=4){pq($pDotsRodXs,$pDotsRodYs,$pDotsRodZs)}

    # return ($pDotsRodXs,$pDotsRodYs,$pDotsRodZs)
}



my ($pDotsLineXs,$pDotsLineYs,$pDotsLineZs);
my ($lineStrains,$tautSegs);
my ($totalLineStretch,$lineDampingPowers);	# For reporting.


my $smoothStrainCutoff		= 0.001;
my $smoothStrainDotsCutoff	= 0.001;

sub Calc_pDotsLineMaterial { use constant V_Calc_pDotsLineMaterial => 1;
    # Uses ($qs,$qDots) = @_;
    # Calc_dQs() must be called first.
    
    ## Enforce line segment constraint as a one-sided, damped harmonic oscillator.
    
    if (!$numLineSegs){return (zeros(0),zeros(0))};
    
    if (DEBUG and V_Calc_pDotsLineMaterial and $verbose>=4){print "\nCalc_pDotsLineMaterial ----\n"}
    
	if (V_Calc_pDotsLineMaterial and DEBUG and $verbose>=4){pq($uLineXs,$uLineYs,$uLineZs)}
    # $lineSegKs already has $segLens built into the denominator, so wants to be multiplied by stretches, not strains.
    my $lineStretches  = $lineDrs-$lineSegLens;

    $lineStrains    = $lineStretches/$lineSegLens;
    #$tautSegs       = $lineStrains >= 0;
	my $smoothTauts	= 1-SmoothChar($lineStrains,0,$smoothStrainCutoff);
	#if ($verbose>=3){print("\$tautSegs = $tautSegs\n")}

    my $lineTensions = -$smoothTauts*$lineStretches*$lineSegKs;
		# I do it this way for historical reasons.  Could implement using SmoothZeroLinear() and a different definition of $lineSegKs.
	if ($verbose>=3){
		ppf("\$smoothTauts   =\t","%7.4f\t",$smoothTauts);
		ppf("\$lineStretches =\t","%7.3f\t",$lineStretches);
		ppf("\$lineStrains   =\t","%7.4f\t",$lineStrains);
		ppf("\$lineTensions  =\t","%7.0f\t",$lineTensions,"\n\n");
		$totalLineStretch = sum($lineStretches);
			# For finding leader material K.
	}

	my $lineStretchDots =
		$uLineXs*$lineDxDots+$uLineYs*$lineDyDots+$uLineZs*$lineDzDots;
	# Unlike the case for the rod, it is possible for line dr's to be zero.
	my $ii = which(!($lineStretchDots->isfinite));
	if (!$ii->isempty){$lineStretchDots($ii) .= 0}
	my $lineStrainDots	= $lineStretchDots/$lineSegLens;
	
	#$lineDampings = -$lineStretchDots*$lineSegCs;
	#my $lineDampings = -$tautSegs*$lineStretchDots*$lineSegCs;

	# !!! NOTE that my model doesn't have enough local information to support internal damping on contraction, since if a segment of line is stretched from nominal and then the two ends suddenly come together, the flexible line would just bend out of the way rather than resist contraction as a rigid rod would.  Of course, the tension force would still be in play until the segment length becomes less than nominal.  Not understanding this caused peculiar behavior in previous simulations.
	#my $noDampingOnContraction = $lineStretchDots >= 0;
	my $smoothExpandings = ($dampOnlyOnExpansion) ?
		1-SmoothChar($lineStrainDots,0,$smoothStrainDotsCutoff) : 1;
	
	# Internal damping only if taut and expanding:
	my $lineDampings =
		-$smoothTauts*$smoothExpandings*$lineStretchDots*$lineSegCs;

	if ($verbose>=3){
		if ($dampOnlyOnExpansion){ppf("\$smoothExpandings =\t","%7.4f\t",$smoothExpandings)}
		ppf("\$lineStretchDots  =\t","%7.3f\t",$lineStretchDots);
		ppf("\$lineStrainDots   =\t","%7.4f\t",$lineStrainDots);
		ppf("\$lineDampings     =\t","%7.0f\t",$lineDampings,"\n\n");
	
		$lineDampingPowers = $lineDampings * $lineStretchDots;
		if ($verbose>=4){ppf("\$lineDampingPows  =\t","%7.0f\t",$lineDampingPowers,"\n\n")}
	}

	my $lineNetForces	= $lineTensions + $lineDampings;
	#if ($verbose>=3){ppf("\$lineNetForces =\t","%7.1f\t",$lineNetForces,"\n\n")}
	
	$pDotsLineXs = $lineNetForces*$uLineXs;
	$pDotsLineYs = $lineNetForces*$uLineYs;
	$pDotsLineZs = $lineNetForces*$uLineZs;
	
	if (DEBUG and V_Calc_pDotsLineMaterial and $verbose>=4){pq($pDotsLineXs,$pDotsLineYs,$pDotsLineZs)}

}



my ($XTip0,$YTip0,$ZTip0);

sub Calc_TipHoldForce { use constant V_Calc_TipHoldForce => 0;
    my ($t,$tFract) = @_;   # $t is a PERL scalar.
    
    ## For times less than start release, add a force on the fly pulling it toward the initial fly location with magnitude proportional to the distance between the fly and the fixed tip point. Add also a damping term proportional to the fly velocity.  For times before release start time, use the full values of the hold k and c (tFract will = 1).  For times between that ant release end time, tFract will diminish to zero, and we multiply k and c by that fraction.
	
    my ($tipHoldForceX,$tipHoldForceY,$tipHoldForceZ) = map {0} (0..2);
	
    if (DEBUG and V_Calc_TipHoldForce and $verbose>=4){print "Calc_TipHoldForce: t=$t,ts=$tipReleaseStartTime, te=$tipReleaseEndTime, fract=$tFract\n"}
	
    my $dX	= $Xs(-1)-$XTip0;
    my $dY	= $Ys(-1)-$YTip0;
    my $dZ	= $Zs(-1)-$ZTip0;
	
	# Tension toward the original tip location, damping opposite current tip velocity.  However, like a shock-absorber, no damping on extension.  It is not clear that damping is needed, since the line itself has lots. And it is especially unclear if one-sided damping in needed:
	
=begin comment

	my $smoothContraction = $dX*$VXs(-1)+$dY*$VYs(-1)+$dZ*$VZs(-1);
	$smoothContraction =
		SmoothChar($smoothContraction,0,$smoothStrainDotsCutoff);

	
	$tipHoldForceX	= -$holdingK*$dX - $smoothContraction*$VXs(-1)*$holdingC;
	$tipHoldForceY	= -$holdingK*$dY - $smoothContraction*$VYs(-1)*$holdingC;
	$tipHoldForceZ	= -$holdingK*$dZ - $smoothContraction*$VZs(-1)*$holdingC;
	
=end comment

=cut
	$tipHoldForceX	= -$holdingK*$dX - $VXs(-1)*$holdingC;
	$tipHoldForceY	= -$holdingK*$dY - $VYs(-1)*$holdingC;
	$tipHoldForceZ	= -$holdingK*$dZ - $VZs(-1)*$holdingC;
	
	
    if ($verbose>=3){
    	my $heldStretch		= sqrt($dX**2 + $dY**2 + $dZ**2);
		my $heldTension		= $holdingK * $heldStretch;
		my $heldStretchDots	= sqrt(	$VXs(-1)**2+$VYs(-1)**2+$VZs(-1)**2 );
		my $heldDamping		= sqrt(	($VXs(-1)*$holdingC)**2+
									($VYs(-1)*$holdingC)**2+
									($VZs(-1)*$holdingC)**2 );
		print "\$heldStretch = $heldStretch\n\$heldTension = $heldTension\n\$heldStretchDots = $heldStretchDots\n\$heldDamping = $heldDamping\n";
	}
	
	if ($tFract < 1){
		$tipHoldForceX *= $tFract;
		$tipHoldForceY *= $tFract;
		$tipHoldForceZ *= $tFract;
	}

    if (DEBUG and V_Calc_TipHoldForce and $verbose>=4){pq($tipHoldForceX,$tipHoldForceY,$tipHoldForceZ)}

    return($tipHoldForceX,$tipHoldForceY,$tipHoldForceZ);
}



# =============  New, water drag

my $bdyVelMult;    # Include smooth transition from the moving water to the still upper air.  Has the value 1 if fully submerged and 0 if in still air.

my $submergedMult;	# Uses segDiam and nodal z-coordinate to make a smooth transition from submerged to not.


sub Calc_VerticalProfile { use constant V_Calc_VerticalProfile => 1;
    my ($Zs,$typeStr,$bottomDepth,$surfaceVel,$halfVelThickness,$surfaceLayerThickness,$plot) = @_;
    
    # To work both in air and water.  Vel's above surface (y=0) (air) are zero, below the surface from the water profile, except, make a smooth transition at the water surface over the height of the surface layer thickness. This is actually realistic and makes the integrator happier.
    
    my $D   = $bottomDepth;         	# cm
    my $v0  = $surfaceVel;   			# cm/sec
    my $H   = $halfVelThickness;   		# cm
    
    # Set any pos $Zs to 0 (return them to the water surface) and any less than -depth to -depth.
    $Zs = $Zs->copy;    # Isolate pdl.
    my $ok = $D+$Zs>=0;   # Above the bottom
    $Zs = $ok*$Zs+(1-$ok)*(-$D);    # If below the bottom, place at bottom
    
    if (any(!$ok)){
        $DE_status = -2;
        $DE_errMsg  = "ERROR:  Detected a node below the water bottom.  CANNOT PROCEED.  Try increasing bottom depth or stream velocity, or lighten the line components.$vs";
    }
	
    
    my $streamVelZs;
    if ($v0){
        switch ($typeStr) {
            
            case "const" {
                $streamVelZs = $v0 * ones($Zs);
            }
            case "lin" {
                my $a = $D/$v0;
                $streamVelZs = ($D+$Zs)/$a;
            }
            case "exp" {
               # y = ae**kv0, y= a+D+1+Y (Yneg). a=H**2/(D-2H), k = ln((D+a)/a)/v0.
                my $a = $H**2/($D-2*$H);
                my $k = log( ($D+$a)/$a )/$v0;
                $streamVelZs = log( ($a+$D+$Zs)/$a )/$k;
                # $Zs are all non-pos, 0 at the surface.  Depth pos.
            }
        }
    }else{
        $streamVelZs = zeros($Zs);
    }
    
    # If not submerged, make velocity zero except in the surface layer
    $bdyVelMult = SmoothChar($Zs,0,$surfaceLayerThickness);
    if ($verbose>=4){ppf("\$bdyVelMult =\t","%7.3f\t",$bdyVelMult,"\n\n")}
    #pq($surfaceMults);
    $streamVelZs *= $bdyVelMult;
    #pq($streamVelZs);
    
    
    if (defined($plot) and $plot){

        my %opts = (gnuplot=>$gnuplot,xlabel=>"Velocity(ft\/sec)",ylabel=>"Depth(ft)");
        Plot($streamVelZs/$feetToCms,$Zs/$feetToCms,"Velocity Profile along Central Vertical Stream Plane (y=0)",\%opts);
    }
    
    if (DEBUG and V_Calc_VerticalProfile and $verbose>=5){pq($Zs,$streamVelZs)}
    return $streamVelZs;
}


sub Calc_HorizontalProfile { use constant V_Calc_HorizontalProfile => 0;
    my ($Ys,$halfWidth,$exponent,$plot) = @_;
    
    
    my $streamVelYMults;
    if ($exponent >= 2){

        my $Ys  = abs($Ys->copy);    # cms.
        $Ys     /= $halfWidth;
		
        #pq($Ys);
        $streamVelYMults = 1/($Ys**$exponent + 1);
        

    } else {
        $streamVelYMults = ones($Ys);
    }
    
    if (defined($plot) and $plot){
        my $plotMat = ($Ys->glue(1,$streamVelYMults))->transpose;
        
        my %opts = (gnuplot=>$gnuplot,xlabel=>"Signed distance (y value) from Stream Center(ft)",ylabel=>"Multiplier");
        Plot($Ys/$feetToCms,$streamVelYMults,"Horizontal Multiplier of Central Velocities",\%opts);
        #PlotMat($plotMat,0,"Horizontal Vel Multiplier vs Distance(ft)");
    }
    
    if (DEBUG and V_Calc_HorizontalProfile and $verbose>=5){pq($Ys,$streamVelYMults)}
    return ($streamVelYMults);
}


# A check on our drag specs and the resultant drag forces:
my $minFreeSinkSpeed    = 0 * $inchesToCms;		# cm/sec
my $maxFreeSinkSpeed    = 50 * $inchesToCms;	# cm/sec

sub Calc_FreeSinkSpeed {
    my ($dragSpecs,$segDiam,$segLen,$segMass) = @_;
	
	my $segWtDynes = $segMass*$surfaceGravityCmPerSec2;
    
    my $speed = sclr(brent(\&FreeSink_Error,
                            pdl($minFreeSinkSpeed),pdl($maxFreeSinkSpeed),1e-5,100,
                            $dragSpecs,$segDiam,$segLen,$segWtDynes));

	if (wantarray){
		my ($FDrag,$CDrag,$RE)	=
			Calc_SegDragForces($speed,1,$dragSpecs,$segDiam,$segLen);
		#pq($FDrag,$CDrag,$RE);
		return ($speed,$FDrag,$CDrag,$RE);
	} else {
		return $speed;
	}

	#return wantarray ? ($speed,$FDrag,$CDrag,$RE) : $speed;
}

sub FreeSink_Error {
    my ($speed,$dragSpecs,$diam,$len,$wt) = @_;
		# Expects weight force in dynes.

    my $error = Calc_SegDragForces($speed,1,$dragSpecs,$diam,$len) - $wt;
    #pq($error);
    
    return $error;
}



sub Calc_SegDragForces { use constant V_Calc_SegDragForces => 0;
    my ($speeds,$submergedMult,$dragSpecs,$segDiams,$segLens,$isNormal) = @_;
    ## Usually, just segs, not fly pseudo-seg, but make a separate call (normal only) with nominal diam and len for the fly.
	
	## The validity of this calculation for axial drag is questionable, since that situation is all about boundary layer details. See refs in Calc_Drags(). I'm really just faking it in this case, but for sure the characteristic length in the RE should be more like the segment length rather than the  diameter.  But, not really the segment length, since the axial drag just depends on the instantaneous line configuration, not on how it is divided up!
	
	# Our Reynolds numbers range from about 100 for gravitational sink in water to 10,000 for casting in air.
	
	my $nargin = @_;
	if ($nargin<6){$isNormal = 1}
    
    my ($mult,$power,$min);
    $mult   = $dragSpecs(0)->sclr;
    $power  = $dragSpecs(1)->sclr;
    $min    = $dragSpecs(2)->sclr;
    #pq($mult,$power,$min);
	#carp "Who called me??\n";
	
	# This is not very accurate physically, but should help keep the solver happy:
    my $fluidKinematicViscosities
        = $submergedMult*$waterKinematicViscosity + (1-$submergedMult)*$airKinematicViscosity;
    my $fluidDensties
        = $submergedMult*$waterDensity + (1-$submergedMult)*$airDensity;
	
    #pq($speeds);

	my $charLens	= ($isNormal) ? $segDiams : $segLens;
    my $REs			= ($speeds*$charLens)/$fluidKinematicViscosities;
	#pq($REs);
    if (DEBUG and V_Calc_SegDragForces and $verbose>=4){print "CHECK THIS: At least temporarily, am bounding RE's away from zero.\n"}
    my $minRE = 0.01;
    my $ok = $REs > $minRE;
    $REs = $ok*$REs + (1-$ok)*$minRE;
    
    my $CDrags  = $mult*$REs**$power + $min;
    my $FDrags  = $CDrags*(0.5*$fluidDensties*($speeds**2)*$segDiams*$segLens);
	#pq($isNormal,$FDrags,$CDrags,$REs);
	
    if (V_Calc_SegDragForces and $verbose>=5){
		pq($REs,$CDrags,$FDrags);
		print "\n";
	}
    
	return wantarray ? ($FDrags,$CDrags,$REs) : $FDrags;
}


my ($flySpeed,$flyDrag);	# For reporting.

sub Calc_Drags { use constant V_Calc_Drags => 1;
    # Pre-reqs: Calc_dQs(), Calc_Qs(), and Calc_QDots().
    
    ## Calculate the viscous drag force at each node implied by the cartesian velocities there interacting with nominal segment that is the sum of the two half segments on either side of the node..
    
    # Water friction contributes drag forces to the line.  I use different normal and axial "moduli" to account for probably different form factors.  I would probably be more correct to use the real water friction coeff, and appropriately modelled form factors.  In any case, the drag coeffs should be proportional to section surface area.  Eventually I might want to acknowledge that the flows around the rod's hex section and the lines round section are different.
    
    # I use an arbitrary cartesian Vs vector to compute the corresponding viscous deceleration vector.  I assume (quite reasonable given our typical numbers) that we remain enough below Reynolds numbers at which complex effects like the drag crisis come into play that the drag force is well enough modeled by a general quadratic function of the velocity (including the linear part, although this is probably unimportant).
    
    
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
    
    
    if (DEBUG and V_Calc_Drags and $verbose>=4){print "\nCalcDrags ----\n"}
	
    # Get the segment-centered relative velocities:
    #if (DEBUG and V_Calc_Drags and $verbose>=4){pq($VXs,$VYs,$VZs)}
    
    my $relVXs = -$VXs->copy;
    my $relVYs = -$VYs->copy;
    my $relVZs = -$VZs->copy;
    
    #if (DEBUG and $verbose>=4){pq($relVXs,$Zs)}
	
	my $fluidVXs;
    if (!$airOnly){
        # Need modify only vx, since fluid vel is parallel to the X-direction.
        $fluidVXs =
            Calc_VerticalProfile($Zs,$profileStr,$bottomDepth,$surfaceVel,$halfVelThickness,$surfaceLayerThickness);
        
        if ($horizExponent >= 2){
            my $mults = Calc_HorizontalProfile($Ys,$horizHalfWidth,$horizExponent);
            $fluidVXs *= $mults;
        }
        
        #if ($verbose>=3){print("\$fluidVXs = $fluidVXs\n")}
        
        $relVXs += $fluidVXs;
        if (DEBUG and V_Calc_Drags and $verbose>=5){pq($fluidVXs)}
    }
	
    # Deal first with just the segment drags, ignoring the fly drag.
	
	# Build nominal segments at the nodes:
	my $extendedDxs = ($dxs/2)->glue(0,pdl(0));
	my $extendedDys = ($dys/2)->glue(0,pdl(0));
	my $extendedDzs = ($dzs/2)->glue(0,pdl(0));
	
	my $nodeDxs		= $extendedDxs(0:-2)+$extendedDxs(1:-1);
	my $nodeDys		= $extendedDys(0:-2)+$extendedDys(1:-1);
	my $nodeDzs		= $extendedDzs(0:-2)+$extendedDzs(1:-1);
	#if ($verbose>=3){pq($nodeDxs,$nodeDys,$nodeDzs)}
	
	my $nodeLens	= sqrt($nodeDxs**2+$nodeDys**2+$nodeDzs**2);
	#if ($verbose>=3){pq($nodeLens)}
	
    my $uDxs = $nodeDxs/$nodeLens;
    my $uDys = $nodeDys/$nodeLens;
    my $uDzs = $nodeDzs/$nodeLens;

    # convert any nan's to zeros.
    my $ii = which(!$nodeLens);
    if (!$ii->isempty){
        $uDxs($ii) .= 0;
        $uDys($ii) .= 0;
        $uDzs($ii) .= 0;
    }
	#if ($verbose>=3){pq($uDxs,$uDys,$uDzs)}
	
    # Project to find the axial and normal (rotated CCW from axial) relative velocity components at the segment cgs:
    my $projAs  = $uDxs*$relVXs + $uDys*$relVYs + $uDzs*$relVZs;
    my $signAs  = $projAs <=> 0;
    #pq($signAs);
    
    my $speedAs = abs($projAs);
    #pq($projAs,$speedAs);
	
    # Use Gram-Schmidt to find the normal relative velocity vectors:
    my $relVNXs    = $relVXs - $projAs*$uDxs;
    my $relVNYs    = $relVYs - $projAs*$uDys;
    my $relVNZs    = $relVZs - $projAs*$uDzs;
    #pq($relVNXs,$relVNYs,$relVNZs);
    
    my $speedNs = sqrt($relVNXs**2 +$relVNYs**2 +$relVNZs**2);
    #pq($speedNs);
    my $nDxs	= $relVNXs/$speedNs;
    my $nDys	= $relVNYs/$speedNs;
    my $nDzs	= $relVNZs/$speedNs;
    
    # Replace any NaN's with zeros:
    $ii = which(!$speedNs);
    if (!$ii->isempty){
        $nDxs($ii) .= 0;
        $nDys($ii) .= 0;
        $nDzs($ii) .= 0;
    }
	
   #pq($speedNs,$submergedMult,$dragSpecsNormal,$segDiams,$nodeLens);
    my $FNs = Calc_SegDragForces($speedNs,$submergedMult,
                                    $dragSpecsNormal,$segDiams,$nodeLens,1);
    my $FAs = Calc_SegDragForces($speedAs,$submergedMult,
                                    $dragSpecsAxial,$segDiams,$nodeLens,0);

	
	my ($lineSpeedsNormal,$lineSpeedsAxial,$lineDragsNormal,$lineDragsAxial);	# For reporting.

	if ($verbose>=3 and $numLineSegs){
		$lineSpeedsNormal	= $speedNs($nRodSegs:-1)->copy;
		$lineSpeedsAxial	= $speedAs($nRodSegs:-1)->copy;
		$lineDragsNormal	= $FNs($nRodSegs:-1)->copy;
		$lineDragsAxial		= $FAs($nRodSegs:-1)->copy;
	}
    #if ($verbose>=3){pq($FNs,$FAs)}
    #if (DEBUG and V_Calc_Drags and $verbose>=4){pq($FNs,$FAs)}

    # Add them component-wise to get the resultant cartesian forces. Drag forces point in the same direction as the relative velocities, hence the plus signs below.  NOTE, however, that the positive $FNs are correct because the normal vectors were define to point in the same hemisphere as the relative velocities, WHEREAS the $FAs must be sign corrected to match the projections:
    $FAs *= $signAs;
    
    $dragXs .= $uDxs*$FAs + $nDxs*$FNs;
    $dragYs .= $uDys*$FAs + $nDys*$FNs;
    $dragZs .= $uDzs*$FAs + $nDzs*$FNs;
    #pq($dragXs,$dragYs,$dragZs);
	
    # We have computed axial and normal drags as if all the segments were taut.  Later I will modify these for the slack segements.  Of course, all the rod segments are taut.    if ($verbose>=3){pq($uXs,$uYs,$VAs,$VNs,$FAs,$FNs,$dragXs,$dragYs)}

    
=begin comment

ENABLE ME!

    if ($nLineSegs and any(!$tautSegs)){
        # Adjust the slack segments as a strain-weighted combination of the taut drag and drag for a locally randomly oriented line.  These random drags point exactly opposite the original velocities, of course, independent from the nominal line seg orientation. (The "which" method works in peculiar ways around no slack segs.):
        
        my $tCoeffs = zeros($nThetas)->glue(0,-$lineStrains*(!$tautSegs));  # Between 1 at full and 0 at no slack.
        #pq($tautSegs,$lineStrains,$tCoeffs);
        
        # I can use the axial and normal Vs here too.
        my $tFRandNs    = -$segFluidMultRand*$VN2s;
        my $tFRandAs    = -$segFluidMultRand*$VA2s;
        
        $FNs = $tCoeffs*$tFRandNs + (1-$tCoeffs)*$FNs;
        $FAs = $tCoeffs*$tFRandAs + (1-$tCoeffs)*$FAs;
    }

=end comment

=cut
	
    # Add the fly drag to the line (or if none, to the rod) tip node. No notion of axial or normal here:
	$flyDrag = 0;
	
    $flySpeed = sqrt($relVXs(-1)**2 + $relVYs(-1)**2 + $relVZs(-1)**2);

    if ($flySpeed){
        
        my $flyIsSubmerged  = $submergedMult(-1);
        $flyDrag   =
            Calc_SegDragForces($flySpeed,$flyIsSubmerged,
                                $dragSpecsNormal,$flyNomDiam,$flyNomLen,1);

        my $flyDragX  = $flyDrag*$relVXs(-1)/$flySpeed;
        my $flyDragY  = $flyDrag*$relVYs(-1)/$flySpeed;
        my $flyDragZ  = $flyDrag*$relVZs(-1)/$flySpeed;
		
		$dragXs += $flyDragX;
		$dragYs += $flyDragY;
		$dragZs += $flyDragZ;
    }

	# Always report forces if writing to terminal:
	if ($verbose>=3){
	
		if ($numRodSegs){
		
			my $rodSpeeds = sqrt($rodVXs**2+$rodVYs**2+$rodVZs**2);
			ppf("\$rodSpeeds =\t","%7.1f\t",$rodSpeeds);
			
			if ($verbose>=4){
				ppf("\$rodVXs    =\t","%7.1f\t",$rodVXs);
				ppf("\$rodVYs    =\t","%7.1f\t",$rodVYs);
				ppf("\$rodVZs    =\t","%7.1f\t",$rodVZs,"\n\n");
			}

			my $rodDrags = sqrt($rodDragXs**2+$rodDragYs**2+$rodDragZs**2);
			ppf("\$rodDrags  =\t","%7.0f\t",$rodDrags,"\n\n");

			if ($verbose>=4){
				ppf("\$rodDragXs =\t","%7.0f\t",$rodDragXs);
				ppf("\$rodDragYs =\t","%7.0f\t",$rodDragYs);
				ppf("\$rodDragZs =\t","%7.0f\t",$rodDragZs,"\n\n");
			}
		}
		
		if (!$airOnly){
			ppf("\$fluidVXs        =\t","%7.1f\t",$fluidVXs);
		}
		
		my $lineSpeeds = sqrt($lineVXs**2+$lineVYs**2+$lineVZs**2);
		ppf("\$lineSpeeds      =\t","%7.1f\t",$lineSpeeds);
		
		ppf("\$relSpeedsAxial  =\t","%7.1f\t",$lineSpeedsAxial);
		ppf("\$relSpeedsNormal =\t","%7.1f\t",$lineSpeedsNormal);
		
		ppf("\$lineDragsAxial  =\t","%7.0f\t",$lineDragsAxial);
		ppf("\$lineDragsNormal =\t","%7.0f\t",$lineDragsNormal,"\n\n");
		
		if ($verbose>=4){
			ppf("\$lineVXs    =\t","%7.1f\t",$lineVXs);
			ppf("\$lineVYs    =\t","%7.1f\t",$lineVYs);
			ppf("\$lineVZs    =\t","%7.1f\t",$lineVZs,"\n\n");
		}
		
		my $dragForces = sqrt($lineDragsAxial**2+$lineDragsNormal**2);
		my $attackDegs = atan($lineSpeedsNormal/$lineSpeedsAxial)*180/$pi;
		my $kitingDegs = atan($lineDragsNormal/$lineDragsAxial)*180/$pi;
		$kitingDegs -= $attackDegs;	# My definition of kiting.
		
		ppf("\$dragForces =\t","%7.0f\t",$dragForces);
		ppf("\$attackDegs =\t","%7.1f\t",$attackDegs);
		ppf("\$kitingDegs =\t","%7.1f\t",$kitingDegs,"\n\n");
		
		if ($verbose>=4){
			if (!$airOnly){
				ppf("\$relVXs     =\t","%7.1f\t",$relVXs);
				ppf("\$relVYs     =\t","%7.1f\t",$relVYs);
				ppf("\$relVZs     =\t","%7.1f\t",$relVZs,"\n\n");
			}
			ppf("\$lineDragXs =\t","%7.0f\t",$lineDragXs);
			ppf("\$lineDragYs =\t","%7.0f\t",$lineDragYs);
			ppf("\$lineDragZs =\t","%7.0f\t",$lineDragZs,"\n\n");
		}
	}
    #if (DEBUG and V_Calc_Drags and $verbose>=4){pq($dragForces)}

    # return $dragForces;
}



sub Calc_pDots { use constant V_Calc_pDots => 1;
    my ($t) = @_;   # $t is a PERL scalar.
    
    ## Compute the change in the conjugate momenta due to the internal and cartesian forces.
    
    # To try to avoid sign errors, my convention for this function is that all contributions to $pDots are plus-equaled.  It is the job of each contributing calculator to get its own sign right.
    
    if (DEBUG and V_Calc_pDots and $verbose>=4){print "\nCalc_pDots ----\n"}

    $pDots  .= 0;
	

    if ($numRodSegs){
        Calc_pDotsRodMaterial();
		
    } else {
        ($pDotsRodXs,$pDotsRodYs,$pDotsRodZs) = map {zeros(0)} (0..2);
    }

	if ($numLineSegs){
	
        Calc_pDotsLineMaterial();
		
    } else {
        ($pDotsLineXs,$pDotsLineYs,$pDotsLineZs) = map {zeros(0)} (0..2);
    }
	
	$dxpDots += $pDotsRodXs->glue(0,$pDotsLineXs);
	$dypDots += $pDotsRodYs->glue(0,$pDotsLineYs);
	$dzpDots += $pDotsRodZs->glue(0,$pDotsLineZs);
	#pq($pDots);
	
	$netAppliedForces .= 0;
	
    # Compute contribution to pDots from the applied  forces:
	
	# Figure submerged multiplier.  Used both in buoyancy and fluid drag:
	if ($airOnly){
		$submergedMult = zeros($numSegs);
	} else {
		$submergedMult = SmoothChar($Zs,-$segDiams/2,$segDiams/2);
	}
    
    if ($calculateFluidDrag){

        Calc_Drags();    # Sets $bdyVelMult:
        #if (V_Calc_pDots and $verbose>=3){pq($dragForces,$bdyVelMult)}
        $netAppliedForces    += $dragForces;
        
        if (!$airOnly){
            my $buoyancyForces
				= $nominalG*$surfaceGravityCmPerSec2*$segVols*$waterDensity*$submergedMult;

            if ($verbose>=3){
				if ($verbose>=4){ppf("\$submergedMult  =\t","%7.3f\t",$submergedMult)}
				ppf("\$buoyancyForces =\t","%7.0f\t",$buoyancyForces);
			}
				
            $netAppliedZs += $buoyancyForces;
        }
    }
 
    my $gravityForces = -$nominalG*$surfaceGravityCmPerSec2*$Masses;
    if ($verbose>=3){ppf("\$gravityForces  =\t","%7.0f\t",$gravityForces,"\n\n");
}
    # Need to recompute if stripping.
    
    $netAppliedZs += $gravityForces;

    if ($numRodSegs and $t < $tipReleaseEndTime ){
		
		#pq($tipReleaseStartTime,$tipReleaseEndTime);
        my $tFract = SmoothChar(pdl($t),$tipReleaseStartTime,$tipReleaseEndTime);
            # Returns 1 if < start time, and 0 if > end time.
		
		my ($tipHoldForceX,$tipHoldForceY,$tipHoldForceZ) =
										Calc_TipHoldForce($t,$tFract);
		
		$netAppliedXs(-1)	+= $tipHoldForceX;
		$netAppliedYs(-1)	+= $tipHoldForceY;
		$netAppliedZs(-1)	+= $tipHoldForceZ;
    }

    if (DEBUG and V_Calc_pDots and $verbose>=4){
        pq($netAppliedXs,$netAppliedYs,$netAppliedZs);
    }
	
	$dxpDots += ($netAppliedXs x $dWs_dws)->flat;
	$dypDots += ($netAppliedYs x $dWs_dws)->flat;
	$dzpDots += ($netAppliedZs x $dWs_dws)->flat;
    #if (V_Calc_pDots and $verbose>=3){pq($pDots)}
    
	
	#pq($dxpDots,$dypDots,$dzpDots);
    
	if (DEBUG and V_Calc_pDots and $verbose>=4){
        print "\n";
        pq($dxpDots,$dypDots,$dzpDots);
        print "\n";
    }
	
	if ($verbose>=3){
		my $time = $t;
		my $fs = sclr($flySpeed);
		my $fd = sclr($flyDrag);
		my $fDiss = -$fs*$fd;
		
		# These are all the external forces, whether conservative or not.
		my $totalAppliedX = sum($netAppliedXs);
		my $totalAppliedY = sum($netAppliedYs);
		my $totalAppliedZ = sum($netAppliedZs);
		
		if ($verbose>=4){
			print "\n";
			pq($totalAppliedX,$totalAppliedY,$totalAppliedZ);
			pq($driverX,$driverY,$driverZ);
			pq($driverXDot,$driverYDot,$driverZDot);
		}
		
		my $transPower =	$driverXDot*$totalAppliedX+
							$driverYDot*$totalAppliedY+
							$driverZDot*$totalAppliedZ;
		
		my $tx = $driverXDot*$totalAppliedX;
		my $ty = $driverYDot*$totalAppliedY;
		my $tz = $driverZDot*$totalAppliedZ;
		if ($verbose>=4){
			pq($tx,$ty,$tz);
			pq($transPower);
		}

		my ($rotPower,$rodBendDissipation,$rodStretchDissipation,$rodDragPower);
		
		if  ($airOnly){
		# In the present model, rotation power goes entirely into the bending potential and frictional dissipation at the handle top joint.
			if ($verbose>=4){
				pq($driverDX,$driverDY,$driverDZ);
				pq($driverDXDot,$driverDYDot,$driverDZDot);
			}
			my $rotSpeed = sqrt($driverDXDot**2+$driverDYDot**2+$driverDZDot**2);
			
			my $rotPowerBend		=	$driverDXDot*$handleBendingForceX +
										$driverDYDot*$handleBendingForceY +
										$driverDZDot*$handleBendingForceZ;
			
			$rotPowerBend			= sclr($rotPowerBend);
			
			my $driverBendC			= sclr($rodBendTorqueCs(0));
			my $rotPowerDiss 		= $rotSpeed*$driverBendC;
			$rotPower 				= $rotPowerBend + $rotPowerDiss;

			if ($verbose>=4){
				pq($rotPowerBend);
				pq($rotSpeed,$driverBendC,$rotPowerDiss);
				pq($rotPower);
			}
			
			$rodBendDissipation		= sum($rodBendDampingPowers);
			$rodStretchDissipation	= sum($rodStretchDampingPowers);
			my $rodDragPowers			=	$rodDragXs*$rodVXs+
											$rodDragYs*$rodVYs+
											$rodDragZs*$rodVZs;
			$rodDragPower			= sum($rodDragPowers);

		}


		my $lineInternalDissipation	= sum($lineDampingPowers);

		my $lineDragPowers	=	$lineDragXs*$lineVXs+
								$lineDragYs*$lineVYs+
								$lineDragZs*$lineVZs;
		my $lineDragPower = sum($lineDragPowers);
		
		if ($airOnly){
			printf("\n*** Handle applied power: translation = %.0e, rotation = %.0e\n",$transPower,$rotPower);
		} else {
			printf("\n*** Rod tip applied power: translation = %.0e\n",$transPower);
		}

		if ($airOnly){
			printf("*** Dissipation: rod(bend,stretch),line = ((%.0e,%.0e),%.0e)\n        drag(rod,line,fly) = (%.0e,%.0e,%.0e)\n",
				$rodBendDissipation,$rodStretchDissipation,
				$lineInternalDissipation,
				$rodDragPower,$lineDragPower,$fDiss);
		} else {
			printf("*** Dissipation(line): internal = (%.0e), drag(line,fly) = (%.0e,%.0e)\n",$lineInternalDissipation,$lineDragPower,$fDiss);
		}
		
		printf("*** t = %.3f; fly speed = %.1f; total line stretch = %.3f\n\n",$time,$fs,,$totalLineStretch);
	}

    # return $pDots;
}



sub Set_HeldTip { use constant V_Set_HeldTip => 1;
    my ($t) = @_;   # $t is a PERL scalar.
    
    # During hold, the ($dxs(-1),$dys(-1)) are not treated as dynamical variables.  Instead, they are made into quantities dependent on all the remaining dynamical varibles and the fixed fly position ($XTip0,$YTip0).  This takes the fly's mass and drag out of the calculation, but the mass of the last line segment before the fly still acts at that segment's cg and its drag relative to its spatial orientation, due to changes in the cg location caused by the motion of the last remaining node ($Xs(-2),$Ys(-2)).
    
    if (!$numLineSegs){die "Hold not allowed if there are no line nodes.Stopped"}
 
    Calc_Driver($t);
	#pq($driverX,$driverY,$driverZ);
	#pq($dxs,$dys,$dzs);
	
    $XTip0 = $driverX+sumover($dxs);
    $YTip0 = $driverY+sumover($dys);
    $ZTip0 = $driverZ+sumover($dzs);
    if (DEBUG and V_Set_HeldTip and $verbose>=3){print "\nSet_HOLD:\n";pq($qs,$XTip0,$YTip0,$ZTip0);print "\n";}
}


sub Get_Tip0 {
    return ($XTip0,$YTip0,$ZTip0);
}



sub DE_GetStatus {
    return $DE_status;
}

sub DE_GetErrMsg {
    return $DE_errMsg;
}

my ($DE_numCalls,$DEfunc_numCalls,$DEjac_numCalls,$DEfunc_dotCount,$DE_reportStep,$DE_driverState,$DE_TemporarilySwitched);
my $DEdotsDivisor = 100;
my $DE_adjustCounter;


sub DE_InitCounts {

    $DE_numCalls        = 0;
    $DEfunc_numCalls    = 0;
    $DEjac_numCalls     = 0;
    $DEfunc_dotCount    = 0;
    #$DE_reportStep      = 1;
    $DE_reportStep      = 0;
	$DE_driverState		= 0;
		# 0 before driver start, 1 during drive, 2 after driver end.
	$DE_TemporarilySwitched = 0;
	$DE_adjustCounter	= 0;
}

sub DE_GetCounts {
    
    return ($DE_numCalls,$DEfunc_numCalls,$DEjac_numCalls,$DEfunc_dotCount);
}


# Integration outputs:
my ($maxTipDiff);
my ($maxLineStrains,$maxLineVs);
my ($plotLineVXs,$plotLineVYs,$plotLineVZs,$plotLineVAs,$plotLineVNs,$plotLine_rDots);

sub DE_InitExtraOutputs {
    
    $maxTipDiff         = zeros(1)->flat;
    
    $maxLineStrains = zeros($numLineSegs);
    $maxLineVs      = zeros($numLineSegs);
    
    $plotLineVXs    = zeros(0);
    $plotLineVYs    = zeros(0);
    $plotLineVZs    = zeros(0);

    $plotLineVAs    = zeros(0);
    $plotLineVNs    = zeros(0);
    $plotLine_rDots = zeros(0);
}

sub Get_ExtraOutputs {
    return ($plotLineVXs,$plotLineVYs.$plotLineVAs,$plotLineVNs,$plotLine_rDots);
}


my $averageDt;
my $averageDtIndex;
my $averageDtFIFO;

sub DEAverageDt {
    my ($dt,$initSize)= @_;
    
    if (defined($initSize)){
        $averageDtFIFO  = $dt*ones($initSize);
        $averageDtIndex = 0;
        $averageDt      = $dt;
    } else {
        my $oldDt   = $averageDtFIFO($averageDtIndex)->sclr;
        #pq($dt,$oldDt);
        $averageDtFIFO($averageDtIndex++) .= $dt;
        if ($averageDtIndex >= $averageDtFIFO->nelem){$averageDtIndex = 0}
        $averageDt  += ($dt-$oldDt)/($averageDtFIFO->nelem);
        #pq($averageDt,$averageDtFIFO);
    }
    #pq($dt,$averageDt);
    return $averageDt;
}



sub Get_movingAvDt {
    return $DE_movingAvDt;
}


sub DE { use constant V_DE => 1;
    
    ### WARNING:  This function takes the radical step of altering the GLOBAL $verbose to allow inspection separately of the jacobian and stepper behavior.
    
    my $saveVerbose = $verbose;
    
    #my $verbose = $verbose;    # Sic, isolate the global from possible change here.
    my ($t,$caller)= @_;  # The args are PERL scalars.  The only callers are "DEfunc_GSL" and "DEjac_GSL", both of which load our package global $dynams.
    
    ## Do a single DE step.
    ## Express the differential equation of the form required by RungeKutta.  The y vector flat (or a row vector).
    my $nargin = @_;

    my $printingCaller = (DEBUG eq "DEjac_GSL")?"DEjac_GSL":"DEfunc_GSL";
    
    if (V_DE and $caller ne $printingCaller){$verbose = 0}
    # Here is where we turn all the functions printing off.
    
    my $progStr = '';
    my $dt      = undef;
    $DE_numCalls++;
    if (V_DE and $caller eq "DEfunc_GSL"){
        if ($DE_numCalls != $DE_lastSteppingCall+1){
            $progStr    = ",SEQUENCE BREAK";
        }
        $dt      = $t-$DE_lastSteppingT;
        if($dt<0){$progStr = ",RETREATING"}
        elsif($dt>0){
            $DE_movingAvDt = DEAverageDt($dt);
            if ($t>$DE_maxAttainedT){
                $DE_maxAttainedT = $t;
                $progStr = ",PROGRESSING";
            }
        }
        $DE_lastSteppingCall = $DE_numCalls;
        $DE_lastSteppingT    = $t;
    }

    $tDynam = $t;

    #print "Before Switch: verbose=$verbose\n";
    if ($switchVerbose and V_DE and $caller eq "DEfunc_GSL" and $verbose<$debugVerbose and $DE_movingAvDt < 0.01*$dT0){
        printf( "\n\n!!! t=%.10f, SOLVER HAS REDUCED THE RUNNING AVERAGE TIMESTEP (%.4e) TO 0.01\nTIMES THE ORIGINAL t0. WE ARE SWITCHING TO \$verbose=$debugVerbose TO SHOW MORE DETAILS.\nLOOK FOR OUTPUT IN THE TERMINAL WINDOW.  OUTPUT THERE MAY BE SEARCHED AND SAVED.  !!!\n",$t,$DE_movingAvDt);
        &{$runControlPtr->{callerChangeVerbose}}($debugVerbose);
        print "\n!!!  BEGINNING SWITCHED DEBUGGING OUTPUT.  !!!\n";
        $saveVerbose = $verbose;
    }

     if (!$DE_TemporarilySwitched and V_DE and $caller eq "DEfunc_GSL" and $verbose>$restoreVerbose and $DE_movingAvDt > 0.04*$dT0){
        &{$runControlPtr->{callerChangeVerbose}}($restoreVerbose);
        printf("\n\n!!! t=%.10f, SOLVER APPEARS TO HAVE GOTTEN PAST THE HARD STRETCH. WE HAVE SWITCHED\nBACK TO THE ORIGINAL VERBOSITY.  !!!\n\n",$t);
        $saveVerbose = $verbose;
    }
	
    if (V_DE and $verbose>=3){
        printf("\n  Entering DE (t=%.8f,dt=%.8f$progStr,caller=$caller),call=$DE_numCalls ...\nmovingAvDt=%.12f\n\n",$t,$dt,$DE_movingAvDt);
    }
    
    if (V_DE and $verbose>=4){
        pq($dxs,$dys,$dzs);
    }
    
    if (V_DE and $verbose>=4){
        pq($dxps,$dyps,$dzps);
    }
    
    if (DEBUG and V_DE and $verbose>=5){pq($qs,$ps)};

    my $dynamDots   = zeros($dynams);

   # Run control from caller:
    &{$runControlPtr->{callerUpdate}}();
    if ($runControlPtr->{callerRunState} != 1) {
    
        $DE_errMsg  = "User interrupt";
        $DE_status  = 1;
        $verbose    = $saveVerbose;
        return ($dynamDots);
    }

	if ($stripping < 0 and $t > $stripStartTime){
		$stripping = 1;
		#print("DE: ");pq($t,$stripping);
	}

	if ($stripping == 1){AdjustFirstSeg_STRIPPING($t)}

=begin comment
	
	if ($stripping < 0 and $t > $stripStartTime){
		$stripping = 1; print("DE: ");pq($t,$stripping)}
    if ($stripping == 1 and $DEfunc_dotCount == 1){
	    # Must be done before Calc_dQs(), but must not be done while any single step is being taken.  Unfortunately, the solver doesn't tell us when it starts a new step.
		$DE_adjustCounter++;
		if ($DE_adjustCounter >= 1){
			$DE_adjustCounter = 0;
        	AdjustFirstSeg_STRIPPING($t);
		}
        AdjustFirstSeg_STRIPPING($t);
		#$DE_adjustCounter
    }
=end comment

=cut
    
    Calc_dQs();
    #if (V_DE and $verbose>=4){pq($lineStrains)}
        # Could compute $Qs now, but don't need them for what we do here.
	
    # Set global coords and external velocities.  See Set_ps_From_qDots():
    Calc_Driver($t);
    # This constraint drives the whole cast. Updates the driver globals.
    
    #Calc_ExtQDots();
    #if (DEBUG and V_DE and $verbose>=4){pq($extQDots);print "D\n";}
       # The contribution to QDots from the driving motion only.  This needs only $dQs_dqs.  It is critical that we DO NOT need the internal contributions to QDots here.
    
    Calc_qDots();
    #if (DEBUG and V_DE and $verbose>=4){pq($dxDots,$dyDots,$dzDots);print "E\n";}
        # At this point we can find the NEW qDots.  From them we can calculate the new INTERNAL contributions to the cartesian velocities, $intVs.  These, always in combination with $extQDots, making $Qdots are then used for then finding the contributions to the NEW pDots due to both KE and friction, done in Calc_pDots() called below.
	
	if ($t<$tipReleaseEndTime or $calculateFluidDrag){Calc_Qs()}
    
    Calc_QDots();
    #if (DEBUG and V_DE and $verbose>=4){pq($QDots);print "F\n";}
    # Finds the new internal cartesian velocities and adds them to $extQDots computed above.

    Calc_pDots($t);
    #if (DEBUG and V_DE and $verbose>=4){pq($pDots);}
    
    $dynamDots(0:$nqs-1)        .= $qDots;
    $dynamDots($nqs:2*$nqs-1)   .= $pDots;
	
	if ($driverEndTime > $driverStartTime){
		if ($verbose>=2 and $DE_driverState == 0 and $t >= $driverStartTime){
			printf("\n!! DRIVER MOTION STARTING  !!\n\n");
			$DE_driverState = 1;
		}
		if ($verbose>=2 and $DE_driverState == 1 and $t >= $driverEndTime){
			printf("\n!! DRIVER MOTION ENDING  !!\n\n");
			$DE_driverState = 2;
		}
	}

    # To indicate progress, tell the user when the solver first passes the next reporting step.  Cf "." in DEfunc_GSL() and "_" in DEjacHelper_GSL():
	if ($verbose>=2 and $reportVerbose and $DE_TemporarilySwitched){
		$DE_TemporarilySwitched = 0;
        &{$runControlPtr->{callerChangeVerbose}}($restoreVerbose);
		$saveVerbose = $verbose;
		#pq($DE_TemporarilySwitched);
	}
    
    if ($verbose>=2 and $t >= $T0+$DE_reportStep*$dT){
        printf("\nt=%.3f   ",$tDynam);
        $DE_reportStep++;
		
		#my $printPeriodicVerbose = $reportVerbose;
		#pq($printPeriodicVerbose);
 
		# We only get here if caller is DEfunc_GSL().  If the user has selected periodic switching, go to higher verbosity here:
		if ($reportVerbose) {
			&{$runControlPtr->{callerChangeVerbose}}($reportVerbose);
			#print "\n!!!  BEGINNING PERIODICALLY SWITCHED DEBUGGING OUTPUT.  !!!\n";
			$saveVerbose = $verbose;
			$DE_TemporarilySwitched = 1;
			#pq($DE_TemporarilySwitched);
		}
    }
	
    if (DEBUG and V_DE and $verbose>=4){pq($dynamDots);print"\n"}
    if (V_DE and $verbose>=3){print "  ... Exiting DE\n"}
    
    # Restore global to it
    $verbose    = $saveVerbose;
    return ($dynamDots);   # Keep in mind that this return is a global, and you may want to make a copy when you make use of it.
}                                                                            



sub DEfunc_GSL { use constant V_DEfunc_GSL => 1;
    my ($t,@aDynams) = @_;
    
    ## Wrapper for DE to adapt it for calls by the GSL ODE solvers.  These do not pass along any params beside the time and dependent variable values, and they are given as a perl scalar and perl array.  Also, the first call is made with no params, and requires the initial dependent variable values as the return.
	
    if (DEBUG and V_DEfunc_GSL and $verbose>=5){print "\n Entering DEfunc_GSL ----\n"}

    if ($verbose>=2 and $DEfunc_dotCount % $DEdotsDivisor == 0){print "."}
    $DEfunc_dotCount++;     # starts new after each dash.
    $DEfunc_numCalls++;
	
#pq(\@aDynams,$dynams);
    
    $dynams .= pdl(@aDynams);   # Loading my global here.  DE() will use it as is.
        # This pdl call isolates @aDynams from $dynams, so nothing I do will mess up the solver's data.  $dynams is a flat pdl.
    if (DEBUG and V_DEfunc_GSL and $verbose>=5){pq($t,$dynams)}
    
    my ($dynamDots) = DE($t,"DEfunc_GSL");
    if (DEBUG and V_DEfunc_GSL and $verbose>=5){pq($DE_status,$dynamDots)}
    
    my @aDynamDots = $dynamDots->list;

    # AS DOCUMENTED in PerlGSL::DiffEq: If any returned ELEMENT is non-numeric (eg, is a string), the solver will stop solving and return all previously computed values.  NOTE that they seem really to mean what they say.  If you set the whole return value to a string, you (frequently) get a segmentation fault, from which the widget can't recover.
    if ($DE_status){$aDynamDots[0] = "stop$vs"}

    if (DEBUG and V_DEfunc_GSL and $verbose>=5){print "\n ... Exiting DEfunc_GSL ----\n"}

    return @aDynamDots;   # Effectively copies.
}


sub DEjacHelper_GSL { use constant V_DEjacHelper_GSL => 0;
    my ($timeGlueDynams) = @_;  # arg is pdl vect $dynams, no explicit time dependence
    
    if (!defined($timeGlueDynams)){print "XX\n"; die; return pdl(0)->glue(0,pdl(DEfunc_GSL()))}
    # This is never called.
        #pq($$timeGlueDynams);

    my $t   = $timeGlueDynams(0)->sclr;
    $dynams .= $timeGlueDynams(1:-1);
    
    if (V_DEjacHelper_GSL and $verbose>=3){pq($t,$dynams)}
    my ($dynamDots) = DE($t,"DEjac_GSL");
    if (V_DEjacHelper_GSL and $verbose>=3){pq($dynamDots)}
    
    return $dynamDots;  # No first time element after init?
    #    return $dynamDots->copy;
}


my ($JACfac,$JACythresh,$JACytyp);

sub JACInit { use constant V_JACInit => 0;
    
    PrintSeparator("Initialize JAC",4);
    
    $JACfac             = zeros(0);
    #my $ynum0           = DEjacHelper_GSL();
    my $ynum0           = 1 + 2*$nqs;
    $JACythresh         = 1e-8 * ones($ynum0);
    $JACytyp            = zeros($JACythresh);
    if (V_JACInit and $verbose>=4){pq($JACythresh,$JACytyp,$ynum0)}
}


sub JAC_FacInit {
    my ($restartJACfac) = @_;

    PrintSeparator("Initialize JACfac (but help me)",3);
    
=begin comment

    if (defined($restartJACfac)){
        PrintSeparator("Initialize JACfac (restarting)",3);
        $JACfac = $restartJACfac;
        pq($JACfac);

    }else {
        PrintSeparator("Initialize JACfac",3);
        $JACfac = zeros(0);
    }
	
=end comment
	
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

sub DEjac_GSL { use constant V_DEjac_GSL => 1;
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
    
    if (DEBUG and V_DEjac_GSL and $verbose>=4){print "\n\nEntering DEjac_GSL (t=$t)\n"}
    if (DEBUG and V_DEjac_GSL and $verbose>=4){pq(\@aDynams)}
    
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
    #if (DEBUG and V_DEjac_GSL and $verbose>=4){pq($JACfac)}
    
    my $dFdt    = $dfdy(0,:)->flat->unpdl;
    my $dFdy    = $dfdy(1:-1,:)->unpdl;
    if (DEBUG and V_DEjac_GSL and $verbose>=4){pq($JACfac,$nfcalls,$dFdy,$dFdt)}

    return ($dFdy,$dFdt);
}

# Required package return value:
1;

__END__


=head1 NAME

RHamilton3D.pm - A Hamilton's Equations 3D stepper specialized for the RHex
configuration comprising a linear array of elements (rod and line segments)
moving under the influence of time dependent boundary conditions, material
properties, gravity, and fluid (air or water) resistance.  This setup works
for both the 3D swing and cast programs.  In the swing program, the rod segments
are simply eliminated, which simplifies somewhat, but in that case there is
an air-water interface and stream bottom effects that complicate.

=head1 SYNOPSIS

use RHamilton3D;

=head1 GENERAL COMMENTS

Hamilton's equations describe the time evolution of classical dynamical mechanical systems.  The code in this file computes data sufficient for taking single time-steps in the numerical integration of these equations for the system comprising a rod, fly line, leader, tippet and fly moving in air, driven by a specified handle motion.  The full integration simulates fly casting.  A slight further specialization of the code to the system comprising just the rod tip, line, leader, tippet and fly moving in air and water allows the simulation of the fishing technique known as streamer swinging.

There is some extra complication in this code, beyond straight-forward hamilton, that facilitates holding of the fly fixed for a while during the start of a casting motion (imitating water loading, or simply to avoid have to do a back cast) and more complication to facilitate stripping, the act of reducing the amount of line outside the rod tip during swing.  In the present implementation, both holding and stripping require re-initialization of this code at certain critical times, due to entire reasonable limitations on the particular ODE solver used in the callers.

For the moment, only the time-step for the swinging similation is completely implemented in the full 3 spatial dimensions.  That for the casting simulation, which came first historically, is implemented only in 2 dimensions (the vertical plane) in the companion module RHamilton.

Graphical user interfaces for handling the complex parameter sets that define the components and  integration parameters are defined in the scripts RHexSwing3D and RhexCast.  Integration is setup and run by the modules RSwing3D and RCast.

All these scripts and modules, as well as a number of utility modules, and some sample data storage files, are contained in the RHex project folder that contains this module.

There is extensive documentation below.  The section "ABOUT THE CALCULATION" contains a discussion of the physical ideas underlying the calculation as well as an outline of the particular implementation. the modification history of the project is there as well.

This file contains PERL source code, which, for efficient computation, makes heavy use of the PDL family of matrix handling modules with their complex internal referencing, as well as old-fashioned global variables to avoid nearly all data copying.

CODE OVERVIEW: The ode solver calls DEfunc_GSL() and DEjac_GSL(), which both effectively wrap the function DE() that does all the work of effecting a single integration test step.  The inputs to DE() are the current time ($t) and the current values of the dynamical variables ($dynams), both passed by the solver, and the outputs are the time derivatives of the dynamical variables ($dynamDots), which are returned to the solver.

Under the Hamiltonian scheme, each configuration dynamical variable (think position-like, here denoted dqs) is paired with a conjugate variable (think momentum-like, here dps, so dynams comprises the dqs and the dps).  The work is to compute the dqDots and dpDots, and so dynamDots.

DE() calls, in a very particular order, a number of functions that first convert the dynamical variables into cartesian variables for the centers of mass of the various component segments (CGQs), and then compute the critical matrix dCGQs_dqs that relates differential changes in the dynamical variables to differential changes in the cartesian variables.  Subsequent calls in DE() compute the desired dynamical dqDots, from which the cartesian CGQDots can be gotten, and then finally, the desired dynamical dpDots.  Diving down through all these calls from DE() and reading the comments and long function and variable names along the way will hopefully make all the details clear.


=head1 ON FORCES AND CONJUGATE MOMENTA

In the context of Hamilton's equations there is a uniform way to figure the effects of all non-inertial forces (potential, dissipative, rocket motor, etc): for a given system configuration (q and p, thus (see below) qDot) apply the force at an appropriate physical (ie, cartesian) location in the system.  Then make a virtual (partial derivative) variation in just one configuration variable.  This implies a particular (differential) cartesian motion of the force application location.  Figure the differential virtual work done by the force under the motion.  This number is the time change in conjugate momentum associated with the selected configuration variable.

In the Hamilton scheme, p is defined as the qDot partial of the Lagrangian (the full expression for the kinetic energy minus potential energy).  In the elementary situation where the applied forces all arise from ordinary potentials, there is no qDot in the second term, so the definition of p, and thus the relationship between qDot and the p's and q's depends only on the expression for the kinetic energy.  So what about the situation in the previous paragraph where an applied force has a qDot dependence (eg, fluid friction)?  Although such forces do affect the total energy of the system, they are not related to inertial forces, which are only concerned with masses in (ultimately) cartesian motion.  THIS PP NEEDS TO BE BETTER.

In working through the above, it is helpful to keep in mind the example of a massive turntable (one degree of freedom, angular position, and one conjugate momentum, angular momentum (determined from the radial distrubution of mass in the turntable, and angular velocity).  Suppose the turntable is connected at various physical locations to anchored springs (which might or might not pull circumferentially) and also to a collection of dashpots and wind vanes, etc. You can then actually see the discussion of the first paragraph play out. In particular, it seems clear that any velocity dependence of the system on its dashpost (local, physical relative velocity) is fundamentally different from the way time derivatives of the configuration varables interact with the system masses.  It could happen that a dashpot actually sees (and only sees) a qDot, but that should be taken to be an accident.  In the general case, the dashpot velocity may have nothing to do with the system qDot's (eg, wind blowing over the turntable).


=head1 BENDING FORCE AND DAMPING

	This section needs work ...

=over

 From http://en.wikipedia.org/wiki/Euler-Bernoulli_beam_equation
 Energy is 0.5*EI(d2W/dx2)**2, where
 I = hex2ndAreaMoment*diam**4.
	 
=back

NOTE:  Each node provides an elastic force proportional to theta.  The illuminating model is not a series of point-like hinge springs, but rather a local bent rod of uniform section and length equal to the segment length L.  If the rod axis is deformed into a uniform curve whose angle at the center of curvature is theta, L = R*theta, where R is the radius of curvature.  A fiber offset outward from the axis by the amount delta is stretched from its original length L to length (R+delta)*theta, so the change in length is (R+delta)*theta - L = (R+delta)*theta - R*theta = delta*theta, and the proportional change (strain) is delta*theta/L.  By Hook's Law and the definition of the elastic modulus E (= force per square inch needed to make dL equal L, that is, to double the length), we get force equal to (delta/L)*E*dA*theta, where dA is the cross-sectional area of a small bundle of fibers at delta from the axis.  Doing the integration over our hexagonal rod section, (including the compressive elastic forces on fiber bundles offset inward from the axis), we end up with a total elastic force tending to straighten the rod segment whose magnitude is (E*hex2ndAreaMoment*diam**4/L)*theta.  As a check, notice that since E (as we use it here) has units of ounces per square inch, and the hex form constant and theta are dimensionless, the product has units ounce-inches, which is what we require for a torque.  Of course, diam and L must be expressed in the SAME units, here inches.

In more detail (and perhaps more correctly):  The work done by a force on a fiber is the cartesian force at that cartesian stretch times a cartesian displacement.  So want to figure the stretch energy in cartesian.  The cartesian force = E*stretch/L, and the WORK = (E/(2*L))*stretch**2.  So in terms of theta, WORK = (E/(2*L))*(delta*theta)**2 = (E*delta**2/(2*L))*theta**2.  So the GENERALIZED force due to theta is the theta derivative of this -- GenForce(theta) =  (E/L)*(delta**2)*theta. It is the delta**2 that integrates over the area to give the SECOND hex MOMENT, our in our case, the second power fiber count moment.  According to Hamilton, it is the generalized force that gives the time change of the associated generalized momentum.  Therefore, it is what we use in our pDots calculation.


Components of the derivative of potential from stretching or compressing the segment, plus that of potential from bending at the node in 3D:  These leverage the rod fibers in different ways.  Stretching multiplies the fiber modulus by the cross-sectional area then by the linear strain, while bending multiplies it by the 2nd moment and then by the total segment angular deflection divided by the segment length.  In the present implementation, this function expects the length divisions to be incorporated in to the K's.
 
The effects of velocity dependent friction are another matter entirely.  There I expect that the stretching velocity damping is mediated by the molecular dissipation following from local shear, while damping due to bending angle velocity or circumferential velocity at constant bend angle imply additional friction from fibers slipping over one another as they stretch or compress as the bending changes.

Thus stretch damping ought to have an area dependence and be independent of the sign of the strain velocity.  The amount of dissipation will be proportional to the segment length, and so proportional to stretch velocity.

Bend damping internal to fibers is proproportional to integrated strain velocity, so 1st moment times bending velocity divided by length (times, to first order, the fiber length which is constant to zeroth order), so in total, section 1st moment times nodal bending angle velocity.  But here we need to remember to take the absolute values of the strain velocities, so 2 times the one-sided 1st moment.  NOTE that we have the 1st moment since the lever arm of the dissipative force doesn't come into play the way it does for spring force.

The bend damping should be proportional to the second moment.  Just as for force, where the force due to the compression on one side and the extension on the other both add positively to the restoring force, shear friction internal to the fibers doesn't care about any signs, only magnitudes of the shears, so again second moment.

In contrast, slippage of fibers along one another is the same total amount at any distance from the rod axis, so we should have area dependence here. However, the dissipation will be proportional to the local slip velocity times the segment length, which is bend velocity/segLen times segLen, so just bend velocity.



 
=head1 ABOUT THE CALCULATION

WARNING: Not everything below is necessarily up to date.

I treat the rod as made up by connected fixed length segments, spring hinged at their ends.  The hinges are the rod nodes.  There are $numRodNodes of these.  The node at index 0 is the handle top node and that at index $numRodNodes-1 is the rod tip node.  The entire cast is driven by external constraints applied to the handle, in particular specifying the handle top node X and Y coordinates and the handle cartesian theta direction measured relative to vertical (driverX,driverY,driverTheta).  The rod is allowed to flex at its upper handle node.  The rod does not flex at its tip node.  The rod dynamical variables are the hinge angles (dthetas) starting with the upper handle node and running to the node below the rod tip.

The line is also described by a vector of nodes.  The line segments come before their respective nodes, so the first line segment (line index 0) runs from the rod tip node to the first line node, and there is no segment beyond the last line node.  The line is set up to behave like an ideal string, each segment has a nominal length, and we impose an elastic force that tends to keep the segment length no greater than nominal, but allows it to be anything less.  It turns out to be best to work with the line in local cartesian coordinates, that is, the line dynamical variables are dxs and dys, the differences between the cartesian coordinates of adjacent nodes.  There are $numLineSegs.

The ordered list of rod nodes, followed by the ordered list of line nodes comprises the system nodes.  The dynamical variables are listed as (dthetas) followed by (dxs) followed by (dys).  The inertial nodes (those whose masses come into play) run from the first node above the handle top to the line tip node (the fly).

At any time, the state of the dynamical variables fix the cartesian coordinates of all the nodes.  I use initial lower-case letters for dynamical variables and initial capitals for cartesian ones.  I list all the X coords first, followed by all the Y coords.  The values of the dynamical variables fix those of the cartesian, and the dynamical variables together with their velocities fix the cartesian velocities.

Fixed masses are associated with each of the nodes, and as is usual in classical mechanics, the dynamics play out due to interactions between these masses and forces (potential and dissipative) associated with the dynamical variables.

VISCOUS (velocity related) damping, due both to rod and line material physical properties and to fluid friction play a significant part in real world casting dynamics.  Thus, damping must be built into the computational model as well.  Lanczos' treatment of Hamiltonial Mechanics, which forms the basis for our calculations here, does not deal with frictional losses.  So, I am winging it.

The situation for the ROD INTERNAL FRICTION seems most clear cut:  We can think of it as modifying the geometric power fiber stretching and compression mechanism that generates the local bending spring constant ($rodKsNoTip).  (See the comments in RHexCommon.pm just before the declaration of $hex2ndAreaMoment, and in SetupIntegration() below, before the declaration of the local variable $rodSectionMultiplier.)  At a given rod node, the theta partial of the total potential energy is just the value of $rodKsNoTip at the node times theta there, which is the usual Hook's Law force, and this force is therefore the bending energy's contribution to the change in the nodal conjugate momentum.  Internal friction in, and between adjacent, power fibers gives a thetaDot-dependent adjustment to the local elastic force.  I argue that, at a given time, globally (and dynamically), the system cannot distinguish between these two generation MECHANISMs for the local force.  That is, the system's change in (conjugate) momentum is the same for a nodal elastic and an equal valued nodal viscous force.  Thus it is ok to simply add the effects when computing pDotRodLocal.  At this level of calculation, the system doesn't distinguish "holonomic" from "non-holonomic" forces.  Pushing on this a bit, the viscous force correction produces a correction to pDots, which, at the next iteration step corrects ps, and therefore qDots, and consequently, corrects the total system KE to account for the energy lost to friction.

Another approach I tried was just modifying the qDots directly (kinematics), but this seem clearly wrong since it doesn't account for the configurations and magnitudes of the masses being moved.

The bending and stretching drags are "laminar" (well ordered?), and so ought to be linear in velocity.  Line air resistance, ought to have some linear and some quadratic.  Figure our approximate Reynolds number.


Previously, I tried to adjust the nodal friction factors to result in critical damping at each node.  In fact, doing that correctly would require recomputing the spatial distribution of outboard masses at each time.  But even working to a time-independent approximation is actually NOT FAIR for BAMBOO rods!  This is because the fiber damping should be just a property of the material itself, which we have taken to be homogenous along the rod.  The nodal damping should be determined by the fiber damping, the diameter, and a form factor.

The above discussion of internal friction at the rod nodes also applies to the LINE nodes when the line segments are STRETCHED to or beyond their nominal lengths.  I have modelled that situation with a one-sided damped harmonic oscillator.  Again, both the restoring spring and damping forces are local, residing in the line segment, and again they should simply add to modify the corresponding nodal pDot.  Here too, it is at least SOMEWHAT UNFAIR to tweak the nodal damping factors individually toward critical damping, although the line manufacturer could in fact do that.  The final result would still be imperfect due to variable lure mass and also due to variable line configuration during the progression of the cast.

What about fluid damping?  It is MORE COMPLEX, since it's not just a local effect.  BUT line normal friction is obviously important, even critical, in the presence of gravity.

We can see how to handle fluid friction by inspection of the calculation of the effect of gravity.  Gravity is useful in that the manipulation is completely legitimate (taking the qDot partial of the potential energy in the Hamiltonian formulation) while clearly separating the roles of the cartesian force and the geometric leverage in generating a contribution to pDot.  To wit:  For each configuration variable q associated with some node, each outboard node contributes to the PE by its cartesian height Y' times its weight W'.  The partial of this wrt q is dQs_dqs(q,Y')*W'.  The factor on the right is the cartesian force, and that on the left is pure geometry that gives the "leverage" of that force has in generating a time-change in the conjugate momentum p.  If we rotated the whole cartesian system before doing our calculation,  we would have dQs_dqs(q,X')*WX' + dQs_dqs(q,Y')*WY' where WX' and WY' are the components of the weight force vector in the X and Y directions, respectively.


For fluid friction, the outboard nodal force points in some direction (frequently rather normal to the line or rod at that node) and has a magnitude that is a multiple (depending on the local characteristic sizes) of some function of the outboard nodal velocity.  The last formula of the previous paragraph is operative, where now WX' and WY' are the components of the frictional force.  This should be so since the mass dynamics of the whole system should have no way of knowing or caring what particular physical phenomenon (gravity or friction) generated the outboard nodal force.


If the velocity acts linearly, we speak of "viscous" drag.  However, more generally, the velocity enters quadratically, and is well modelled by multiplying V^2 by a "drag coefficient" that is a function of the Reynolds number. Typical line normal Reynolds numbers in our casts are less than 100, frequently much less.  In this region, the drag coefficient is linearly decreasing in log-log coordinates.


OLD   The rod nodes come first, then the line nodes.  The dynamical variables for the rod are the nodal deflection angles stored in the variable thetas.  These are exterior angles, small for small curvature, with positive angles deflecting the rod to the right going toward tip.  It is critical for correct modeling that the line not support compression, while at the same time being extensible only up to a fixed length.  Thus I can't simply constrain the line segment lengths as I do the rod.  I could extend the theta scheme to the line, and let these angles together with the individual segment lengths be the line dynamical variables.  However, since the segment lengths must be allowed to pass through zero and come out the other side, the singularity of polar coordinates at r=0 would require a lot of special handling.  It seems easier to simply use relative cartesian coordinates to locate the line nodes.  My scheme is to have the (dys,dxs) be the coordinates of the next node in the system whose origin is the current node.


=head1 MODIFICATION HISTORY

14/03/12 - Langrangian corrected to include the inertial terms from the kinetic energy into the calculation of the pDots.

14/03/19 - Returned to polar dynamical variables for the line, the better to impliment segment length constraint.

14/03/28 - Returned to cartesian line dynamical variables.  Previous version stored in Development directory as RHCastPolar.pl

14/05/02 - Converted to package to be called from widget and file front ends.

14/05/21 - Added postcast drift.

14/08/15 - Added video frame capture features.

14/08/25 - Added line-tip delayed release mechanism.  Corrected problem with computing nodal spring constants from bamboo elastic modulus.  Relaxed rod nodal spacing.

14/09/03 - Restored line damping RATIO as a parameter, while retaining the ability to directly set the damping MODULUS.

14/09/13 - Installed SmoothChar to implement partitions of unity.  Added velocity squared damping, fly air damping, and curved line initialization.

14/09/27 - Introduced Calc_pDotsCartForces.

4/10/01 - Added leader, removed notion of calc length different from loop length.  Rearranged widget fields, added menubuttons.

14/10/21 - Moved some code to RHexCommonPkg.pm
--- Lots of changes.

14/12/22 - Changed loading functions to read file matrix data into pdl's.  Trying to keep use of perl arrays as infrequent and low-level as possible.  Added reading of integration state from rod file.

15/01/12 - Refined use of $verbose and made it user setable, substituted pq for print where possible.

15/02/06 - Added cut-and-paste documentation, adjusted nav start for save ops.
--- Lots of changes.

17/08/20 - Incorporated PDL's virtual slice mechanism to simplify and possibly speed up data flow in the integration loop.  Corrected two important typo's, one in line tension and one in air drag.  Implemented a more realistic simulation of air drag.

17/08/21 - Redid the way the boundary conditions (principally how the handle motion drives the system) to one that I believe is correct.  The previous method was clearly not right, which I understood by examining the case of no rod segs and just one or two line segs.  The new method just pumps potential energy into the system at each timestep, a procedure explicitly allowed by Lanczos analysis.

17/09/02 - Previous change in bound condition handling might be in principal ok but led to more difficult integration.  On reflection, my problem with directly applied drive contraints was due to a misunderstanding.  It is correct to simply compute external velocities and add them to the internal ones to construct the KE function, then differentiate per Hamilton to get the dynamic ps, solve for qDots, etc.  On the other hand, a soft constraint to implement tip hold works fine, although one could save a bit of computation time by applying a strict constraint before release start time to temporarily eliminate 2 dynamical variables.

17/09/11 - I noticed that with hold implemented via a spring constant on the fly node, increasing the constant made the program run really slowly and didn't do a good job of keeping the fly still.  A small constant did a much better job.  But this makes me think it would be better to just hold the fly via a constraint, eliminating the (dxFly,dyFly) dynamical variable in favor of using the last line segment (between the next-to-last node and the fixed point) to add a force that affects all the pDots in the reduced problem.  I could do this by running the reduced problem up till hold release, and then the full problem, but will try first to see if I can just fake it with the full problem adjusted to keep the fly from moving, while not messing up the movement of the other nodes.

17/10/01 - See RHexStatic (17/09/29).  Understood the model a bit better:  the angles theta are the dynamical variables and act at the nodes (hinges), starting at the handle top and ending at the node before the tip.  The bending at these locations creates torques that tend to straighten the angles (see GradedSections()).  The masses, however, are properly located at the segment cg's, and under the effect of gravity, they also produce torques at the nodes.  In equilibrium, these two sets of torques must cancel.  Note that there is no need for the masses to be in any particular configuration with respect to the hinges or the stretches - the connection is established by the partials matrix, in this case, dCGQs_dqs (in fact, also d2CGQs_d2thetas for Calc_pDotsKE). There remains a delicacy in that the air drag forces should more properly be applied at the segment surface resistance centers, which are generally slightly different from the segment cgs.  However, to avoid doubling the size of the partials matrices, I will content myself with putting the air drags at the cg's.

17/10/08 - For a while I believed that I needed to compute cartesian forces from the tension of the line on the guides.  This is wrong.  Those forces are automatically handled by the constraints.  However, it does make sense to take the length of the section of line between the reel and the first line node (say a mark on the line, always outside the rod tip) as another dynamical variable.  The position of the marked node in space is determined by the seg length and the direction g by the two components of the initial (old-style) line segment.  To first approximation, there need not be any mass associated with the line-in-guides segment since that mass is rather well represented by the extra rod mass already computed, and all the line masses outboard cause the new segment to have momentum.  What might be gained by this extra complication is some additional shock absorbing in the line.


17/10/30 - Modified to use the ODE solver suite in the Gnu Scientific Library.  PerlGSL::DiffEq provides the interface.  This will allow the selection of implicit solvers, which, I hope, will make integration with realistic friction couplings possible.  It turns out to be well known that friction terms can make ODE's stiff, with the result that the usual, explicit solvers end up taking very small time steps to avoid going unstable.  There is considerable overhead in implicit solutions, especially since they require jacobian information.  Providing that analytically in the present situation would be a huge problem, but fortunately numerical methods are available.  In particular, I use RNumJac, a PDL version of Matlab's numjac() function that I wrote.

19/01/01 - RHexHamilton split off from RHexCast to isolate the stepper part of the code.  The remaining code became the setup and caller, still called RHexCast.  A second caller, RSink was created to run the stepper in submerged sink line mode.  This code handles both.

19/01/14 - Stripper mode added to this code, to handle the case where, after an interval of sinking, the line is stripped in through the tip guide.  The implementation draws the first line (inertial) node in toward the rod tip by reducing (as a function of time) the nominal length of the initial segment while simultaneously reducing its mass and adjusting its nominal (CG) diameter, and (perhaps) the relative CG location.  Once the seg len becomes rather short (but no so short that it messes up the computational inverse), this code returns control to the caller, which then takes note of the final cartesian location of the initial inertial node, records as it will, reduces the number of line nodes by 1, removes the associated (dx,dy) dynamical variables, and calls InitHamilton($Arg_T0,$Arg_Dynams0,$X0,$Y0), causing a partial reset of all the dynamical variables here.  The caller then makes a new call to the ODE solver.

19/02/01 - Began 3D version of the hamilton code. At first, will implement only sink version to avoid the complication of dealing with second derivatives in Calc_CartesianPartials.  I will use the convention of a right-hand X,Y,Z coordinate system, with X pointing downstream and Z pointing upward.

19/02/02 - How to choose the rod dynamical variables is a delicate question.  Simply choosing angles relative to say the (X-Y) and (X-Z) planes leaves the possibility of indeterminacy (as, for example, when a rod segment is vertical.  That there is a usable set of dynmaical variables is shown by imagining that each rod node is actually a double (1-D) hinge arrangement, with a first hinge allowing motion in a fixed plane containing the previous segment, and a short segment later, a hinge in the perpendicular direction (as defined when the first hinge is not deflected).  It is clear that the specification of these hinge angles uniquely determines (and is determined by) the rod configuration.

For the moment, I will just insert placeholders for the rod dynamical variables.

19/02/20 - The name sink was replaced by swing, which better reflects 3D nature of the motion and all the new capabilities (3D rod tip motion, water velocity profiles in both stream depth and cross-stream, sink delay and stripping).  I realized, in the context of swing, that the matrix inversion that was so costly and used at every step in Calc_qDots() need only be computed once (during initialzation).  This made the program run much faster.  At the same time, I ruthlessly removed all unnecessary copying.

The code was made more streamlined, especially Calc_pDots(), which now collects all applied CG forces before making a matrix multiplication with dCGQs_dqs.  The verbose system was also cleaned up to make $verbose = 2 the standard user mode, with good progress reporting to the status window, but very little print overhead.  Verbose = 3 is also expected to be helpful to the user, showing the dynamical variables and the CG forces at each integration step, and in the better context of a terminal window, but at the cost of much increased execution time.  $verbose >= 4 is always meant for debugging, and the code is only included if the constant DEBUG flag is set in RCommon.

I believe I understand that I can use the dqs = (dxs,dys,dzs) line cartesian dynamical variables, with their huge saving of not recomputing the inverse (essentially because the KE is not dqs dependent, only dqDots dependent), for the rod as well. This adds the extra expense of one more dynamical variable for each inertial rod node, and the inclusion of the rod segment stretching PE in place of just a fixed segment length constraint, but this will be easily paid for by not having to recompute inv.  I hope to implement this soon.

19/02/20 - Switched to rod handling described in the previous paragraph.  To get swinging working, but leave casting unimplemented at first.

19/02/20 - Began enabling casting.  The driver will be location of the rod handle butt, ($xHandle,$yHandle,$zHandle) together with deltas pointing to the top of the rod handle ($dxHandle,$dyHandle,$dzHandle), never identically zero, and constrained to have constant length equal to $handleLen.

19/04/27 - The previously implemnented hold model didn't work well; too many effects in the last segment not dealt with.  Returning to the earlier method where a holding force is applied to the fly, and this time adding velocity damping to the fly as well. Since the number of segs is now constant during the entire computation, the SetEvents mechanism is not needed. However, I will leave the framework in place, since it would come into play if we ever implement hauling.

=head1 EXPORT

All the exports are used only by RSwing3D.pm and RCast3D.pm.

DEBUG $verbose $debugVerbose Calc_FreeSinkSpeed Init_Hamilton Get_T0 Get_dT Get_movingAvDt Get_TDynam Get_DynamsCopy Calc_Driver Calc_VerticalProfile Calc_HorizontalProfile Get_Tip0 DEfunc_GSL DEjac_GSL DEset_Dynams0Block DE_GetStatus DE_GetErrMsg DE_GetCounts JACget AdjustHeldSeg_HOLD Get_ExtraOutputs

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








