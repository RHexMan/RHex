#!/usr/bin/perl

#############################################################################
## Name:			RHamilton3D.pm
## Purpose:			A Hamilton's Equations 3D stepper specialized for the RHex
##                  configuration comprising a linear array of elements (rod and line
##                  segments) moving under the influence of time dependent boundary
##                  conditions, material properties, gravity, and fluid (air or water)
##                  resistance.
## Author:			Rich Miller
## Modified by:	
## Created:			2014/01/30
## Modified:		2017/10/30, 2018/12/31, 2019/2/21
## RCS-ID:
## Copyright:		(c) 2019 Rich Miller
## License:			This program is free software; you can redistribute it and/or
##					modify it under the same terms as Perl itself
#############################################################################

# syntax:  use RHamilton3D;

# Hamilton's equations describe the time evolution of classical dynamical mechanical systems.  The code in this file computes data sufficient for taking single time-steps in the numerical integration of these equations for the system comprising a rod, fly line, leader, tippet and fly moving in air, driven by a specified handle motion.  The full integration simulates fly casting.  A slight further specialization of the code to the system comprising just the rod tip, line, leader, tippet and fly moving in air and water allows the simulation of the fishing technique known as streamer swinging.

# There is some extra complication in this code, beyond straight-forward hamilton, that facilitates holding of the fly fixed for a while during the start of a casting motion (imitating water loading, or simply to avoid have to do a back cast) and more complication to facilitate stripping, the act of reducing the amount of line outside the rod tip during swing.  In the present implementation, both holding and stripping require re-initialization of this code at certain critical times, due to entire reasonable limitations on the particular ODE solver used in the callers.

# For the moment, only the time-step for the swinging similation is completely implemented in the full 3 spatial dimensions.  That for the casting simulation, which came first historically, is implemented only in 2 dimensions (the vertical plane) in the companion module RHamilton.

# Graphical user interfaces for handling the complex parameter sets that define the components and  integration parameters are defined in the scripts RHexSwing3D and RhexCast.  Integration is setup and run by the modules RSwing3D and RCast.

# All these scripts and modules, as well as a number of utility modules, and some sample data storage files, are contained in the RHex project folder that contains this module.

# There is extensive documentation at the end of this file.  The section "ABOUT THE CALCULATION" contains a discussion of the physical ideas underlying the calculation as well as an outline of the particular implementation. the modification history of the project is there as well.

# This file contains PERL source code, which, for efficient computation, makes heavy use of the PDL family of matrix handling modules with their complex internal referencing, as well as old-fashioned global variables to avoid nearly all data copying.

# CODE OVERVIEW: The ode solver calls DEfunc_GSL() and DEjac_GSL(), which both effectively wrap the function DE() that does all the work of effecting a single integration test step.  The inputs to DE() are the current time ($t) and the current values of the dynamical variables ($dynams), both passed by the solver, and the outputs are the time derivatives of the dynamical variables ($dynamDots), which are returned to the solver.

# Under the Hamiltonian scheme, each configuration dynamical variable (think position-like, here denoted dqs) is paired with a conjugate variable (think momentum-like, here dps, so dynams comprises the dqs and the dps).  The work is to compute the dqDots and dpDots, and so dynamDots.

# DE() calls, in a very particular order, a number of functions that first convert the dynamical variables into cartesian variables for the centers of mass of the various component segments (CGQs), and then compute the critical matrix dCGQs_dqs that relates differential changes in the dynamical variables to differential changes in the cartesian variables.  Subsequent calls in DE() compute the desired dynamical dqDots, from which the cartesian CGQDots can be gotten, and then finally, the desired dynamical dpDots.  Diving down through all these calls from DE() and reading the comments and long function and variable names along the way will hopefully make all the details clear.



# Compile directives ==================================
package RHamilton3D;

use warnings;
use strict;

use Exporter 'import';
our @EXPORT = qw(DEBUG $verbose Init_Hamilton Get_T0 Get_dT Get_TDynam Get_DynamsCopy Calc_Driver Calc_VerticalProfile Calc_HorizontalProfile Get_HeldTip DEfunc_GSL DEjac_GSL DEset_Dynams0Block DE_GetStatus DE_GetErrMsg DE_GetCounts JACget AdjustHeldSeg_HOLD Get_ExtraOutputs);

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

use RPrint;
use RPlot;
use RCommon;
use RNumJac;


# Code ==================================

# Variables here set from args to SetupHamilton():
my ($mode,
    $gravity,$rodLength,$actionLength,
    $numRodNodes,$init_numLineNodes,
    $init_segLens,$init_segCGs,$init_segCGDiams,
    $init_segWts,$init_segBuoys,$init_segKs,$init_segCs,
    $init_flyNomLen,$init_flyNomDiam,$init_flyWt,$init_flyBuoy,
    $dragSpecsNormal,$dragSpecsAxial,
    $segFluidMultRand,
    $driverXSpline,$driverYSpline,$driverZSpline,
    $driverThetaSpline,$driverPhiSpline,
    $driverOffsetTheta,$driverOffsetPhi,
    $frameRate,$driverStartTime,$driverEndTime,
    $tipReleaseStartTime,$tipReleaseEndTime,
    $T0,$Dynams0,$dT,
    $runControlPtr,$programmerParamsPtr,$loadedStateIsEmpty,
    $profileStr,$bottomDepthFt,$surfaceVelFtPerSec,$halfVelThicknessFt,
    $horizHalfWidthFt,$horizExponent,
    $surfaceLayerThicknessIn,
    $sinkInterval,$stripRate);


my ($DE_status,$DE_errMsg);
# The ode_solver returns status -1 on error, but does not give the value to me.  In any case, I avoid that value.  I return 0 if no error, -2 on bottom error, and 1 on user interrupt.

my ($tDynam,$dynams);    # My global copy of the args the stepper passes to DE.
my $numRodSegs;

# Working copies (if stripping, cut down from the initial larger pdls, and subsequently, possibly with first seg readjusted in time):
my ($numLineNodes,$numLineSegs);

my ($segLens,$segCGs,$segCGDiams,
    $segWts,$segBuoys,$segKs,$segCs,
    $rodKsNoTip,$rodCsNoTip,$lineSegKs,$lineSegCs,
    $flyNomLen,$flyNomDiam,$flyWt,$flyBuoy);


my ($rodSegLens,$lineSegLens,$init_lineSegNomLens);
my ($CGWts,$CGQMasses,$CGs,$CGQMassesDummy1,$lowerTriPlus);
my ($calculateFluidDrag,$airOnly,$CGBuoys);
my $holding;
my ($stripping,$stripStartTime);
my ($thisSegStartT,$lineSeg0LenFixed,
    $line0SegWtFixed,$line0SegBuoyFixed,
    $line0SegKFixed,$line0SegCFixed);
my ($HeldSegLen,$HeldSegK,$HeldSegC);


sub Init_Hamilton {
    $mode = shift;
    
    if ($mode eq "initialize"){
        
        my ($Arg_gravity,$Arg_rodLength,$Arg_actionLength,
            $Arg_numRodNodes,$Arg_numLineNodes,
            $Arg_segLens,$Arg_segCGs,$Arg_segCGDiams,
            $Arg_segWts,$arg_segBuoys,$Arg_segKs,$Arg_segCs,
            $Arg_flyNomLen,$Arg_flyNomDiam,$Arg_flyWt,$Arg_flyBuoy,
            $Arg_dragSpecsNormal,$Arg_dragSpecsAxial,
            $Arg_segFluidMultRand,
            $Arg_driverXSpline,$Arg_driverYSpline,$Arg_driverZSpline,
            $Arg_driverThetaSpline,$Arg_driverPhiSpline,
            $Arg_driverOffsetTheta,$Arg_driverOffsetPhi,
            $Arg_frameRate,$Arg_driverStartTime,$Arg_driverEndTime,
            $Arg_tipReleaseStartTime,$Arg_tipReleaseEndTime,
            $Arg_T0,$Arg_Dynams0,$Arg_dT,
            $Arg_runControlPtr,$Arg_programmerParamsPtr,$Arg_loadedStateIsEmpty,
            $Arg_profileStr,$Arg_bottomDepthFt,$Arg_surfaceVelFtPerSec,
            $Arg_halfVelThicknessFt,$Arg_surfaceLayerThicknessIn,
            $Arg_horizHalfWidthFt,$Arg_horizExponent,
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
        $init_segBuoys              = $arg_segBuoys;
        $init_segKs                 = $Arg_segKs->copy;
        $init_segCs                 = $Arg_segCs->copy;
        $init_flyNomLen             = pdl($Arg_flyNomLen);
        $init_flyNomDiam            = pdl($Arg_flyNomDiam);
        $init_flyWt                 = pdl($Arg_flyWt);
        $init_flyBuoy               = pdl($Arg_flyBuoy);
        $dragSpecsNormal            = $Arg_dragSpecsNormal;
        $dragSpecsAxial             = $Arg_dragSpecsAxial;
        $segFluidMultRand           = $Arg_segFluidMultRand;
        $driverXSpline              = $Arg_driverXSpline;
        $driverYSpline              = $Arg_driverYSpline;
        $driverZSpline              = $Arg_driverZSpline;
        $driverThetaSpline          = $Arg_driverThetaSpline;
        $driverPhiSpline            = $Arg_driverPhiSpline;
        $driverOffsetTheta          = $Arg_driverOffsetTheta;
        $driverOffsetPhi            = $Arg_driverOffsetPhi;
        $frameRate                  = $Arg_frameRate;
        $driverStartTime            = $Arg_driverStartTime;
        $driverEndTime              = $Arg_driverEndTime;
        $tipReleaseStartTime        = $Arg_tipReleaseStartTime;
        $tipReleaseEndTime          = $Arg_tipReleaseEndTime;
        $T0                         = $Arg_T0;
        $Dynams0                    = $Arg_Dynams0->copy;
        $dT                         = $Arg_dT;
        $runControlPtr              = $Arg_runControlPtr;
        $programmerParamsPtr        = $Arg_programmerParamsPtr;
        $loadedStateIsEmpty         = $Arg_loadedStateIsEmpty;
        $profileStr                 = $Arg_profileStr;
        $bottomDepthFt              = $Arg_bottomDepthFt;
        $surfaceVelFtPerSec         = $Arg_surfaceVelFtPerSec;
        $halfVelThicknessFt         = $Arg_halfVelThicknessFt;
        $surfaceLayerThicknessIn    = $Arg_surfaceLayerThicknessIn;
        $horizHalfWidthFt           = $Arg_horizHalfWidthFt;
        $horizExponent              = $Arg_horizExponent;
        $sinkInterval               = $Arg_sinkInterval;
        $stripRate                  = $Arg_stripRate;
        
        
        # I will always "initialize" as though there is no stripping or holding, and then let subsequent calls to "restart_stripping" and "restart_holding" deal with those states.  This lets me have the caller do the appropriate adjustments to $Dynams0 (so $dynams).
        
        $stripping  = 0;
        $holding    = 0;
        
        if (defined($sinkInterval)){
            if (!defined($stripRate)){die "ERROR:  In stripping mode, both sinkInterval and stripRate must be defined.\n"}
                $stripStartTime = $T0 + $sinkInterval;
                $thisSegStartT  = $T0;
                if ($verbose>=3){pq($sinkInterval,$stripRate,$T0,$stripStartTime)}
        }
        

        if (!defined($tipReleaseStartTime) or !defined($tipReleaseEndTime)){
            # Turn off release delay mechanism:
            $tipReleaseStartTime    = $T0 - 1;
            $tipReleaseEndTime      = $T0 - 0.5;
        }
        
        # Initialize other things directly from the passed params:
        
        if ($numRodNodes == 0){$numRodNodes = 1};
        # Set to 0 or 1 to indicate no rod.  If there is a rod, includes handle top node and tip, so at least 2 nodes.  Otherwise, the single rod node is the tip, which is not inertial.
        #pq($nRodNodes);
        $numRodSegs     = $numRodNodes - 1;
 
        $numLineNodes   = $init_numLineNodes;
        $numLineSegs    = $numLineNodes;
        
        $airOnly = (!defined($profileStr))?1:0;    # Strange that it requires this syntax to get a boolean.
        
        
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
    
    # Need do this just this once:
    Calc_CartesianPartials();    # Needs the helper PDLs and slices to be defined
    Calc_KE_Inverse();


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
    $DE_errMsg          = "";
    

}

my $numSegs;

sub Init_WorkingCopies {
    
    PrintSeparator("Making working copies",3);
    
    if ($verbose>=3){pq($numRodSegs,$init_numLineNodes,$numLineNodes)}
    
    $numSegs    = $numRodSegs + $numLineSegs;

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
    my $iKeeps  = $iRods->glue(0,$iLines);  ### NOT RIGHT IN 3D.
    if ($verbose>=3){pq($init_segLens)}
    #pq($iRods,$iLines,$iKeeps);

    $segLens    = $init_segLens->dice($iKeeps)->copy;
    $segCGs     = $init_segCGs->dice($iKeeps)->copy;
    $segCGDiams = $init_segCGDiams->dice($iKeeps)->copy;
    $segWts     = $init_segWts->dice($iKeeps)->copy;
    $segBuoys   = $init_segBuoys->dice($iKeeps)->copy;
    $segKs      = $init_segKs->dice($iKeeps)->copy;
    $segCs      = $init_segCs->dice($iKeeps)->copy;
 
    if ($verbose>=3){pq($segLens,$segCGs,$segCGDiams,$segWts,$segBuoys,$segKs,$segCs)}


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
   
    $lineSegLens        = $segLens->dice($iiiKeeps);
    my $lineSegWts      = $segWts->dice($iiiKeeps);
    my $lineSegBuoys    = $segBuoys->dice($iiiKeeps);
    $lineSegKs          = $segKs->dice($iiiKeeps);
    $lineSegCs          = $segCs->dice($iiiKeeps);

    if (DEBUG and $verbose>=4){pq($rodSegLens,$lineSegLens)}

    # Make some copies to be fixed for this run:
    if ($stripping == 1){
        $lineSeg0LenFixed       = $lineSegLens(0)->copy;
        $line0SegWtFixed        = $lineSegWts(0)->copy;
        $line0SegBuoyFixed      = $lineSegBuoys(0)->copy;
        $line0SegKFixed         = $lineSegKs(0)->copy;
        $line0SegCFixed         = $lineSegCs(0)->copy;
    }
    
    if ($holding == 1){
        $HeldSegLen = $init_segLens(-1);
        $HeldSegK   = $init_segKs(-1);
        $HeldSegC   = $init_segCs(-1);
    }
    
    # Implement the conceit that when holding == 1 the last seg specs are attributed to the fly, and athe calculation is done without the original last seg's dynamical veriables.  Weights at all inertial nodes for use in Calc_pDotsGravity().  The contribution to the forces from gravity for the line is independent of the momentary configuration and so can be computed in advance here.
    $flyNomLen      = ($holding == 1) ? $init_segLens(-1) : $init_flyNomLen;
    $flyNomDiam     = ($holding == 1) ? $init_segCGDiams(-1) : $init_flyNomDiam;
    $flyWt          = ($holding == 1) ? $init_segWts(-1) : $init_flyWt;
    $flyBuoy        = ($holding == 1) ? $init_segBuoys(-1) : $init_flyBuoy;
        # For parallelism.  Actually there never will be tip holding when swinging.
    
    $CGWts          = $segWts->glue(0,$flyWt);

    my $CGmasses    = $massFactor*$CGWts;
    $CGQMasses      = $CGmasses->glue(0,$CGmasses)->glue(0,$CGmasses);    # Corresponding to X, Y and Z coords of all segs and the fly pseudo-seg.
    if ($verbose>=3){pq $CGQMasses}
    
    my $flyCG   = ($holding == 1) ? $init_segCGs(-1) : pdl(1);
    $CGs        = $segCGs->glue(0,$flyCG);
    
    if ($verbose>=3){pq($holding,$CGWts,$CGQMasses,$flyCG,$CGs)}
        

    # Prepare "extended" lower tri matrix used in constructing dCGQs_dqs in Calc_CartesianPartials():
    my $extraRow        = ($holding == 1) ? zeros($numSegs) : ones($numSegs);
    $lowerTriPlus   = LowerTri($numSegs,1)->glue(1,$extraRow);
    if (DEBUG and $verbose>=4){pq($holding,$lowerTriPlus)}
    # Extra row for fly weight.
        

    my $CGForcesGravity    = -$gravity*$CGWts;
    if ($verbose>=3){pq($CGForcesGravity)}
    
    
    if (!$airOnly){
        
        # No holding in sink implentation.
        $CGBuoys    = $segBuoys->glue(0,$flyBuoy);
        if (DEBUG and $verbose>=4){pq($CGBuoys)}

        my $CGForcesSubmergedBuoyancy = $gravity*$CGBuoys;
        if ($verbose>=3){pq($CGForcesSubmergedBuoyancy)};
        
        my $CGForcesSubmergedNet     = $CGForcesGravity + $CGForcesSubmergedBuoyancy;
        if ($verbose>=2 and ($mode eq "initialize")){pq($CGForcesSubmergedNet)};
    }
}
    

my $smallNumber     = 1e-8;
my $smallStrain     = 1e-6;
my $smallStretch    = $smallStrain * 12;   # Say typical segLen is 12 inches.
my $KSoftRelease    = 100; # Used only for soft release.


# Use the PDL slice mechanism in the integration loop to avoid as much copying as possible.  Except where reloaded (using .=); must be treated as read-only:

# Declare the dynamical variables and their useful slices:
my ($nSegs,$nRodSegs,$nLineSegs,$nRodNodes,$nLineNodes,$nINodes,$nQs,$nCGs,$nCGQs,$nqs);

my $dynamDots;
my ($idx0,$idy0,$idz0);
my ($qs,$dxs,$dys,$dzs,$drs);
my ($ps,$dxps,$dyps,$dzps);
my ($qDots,$dxDots,$dyDots,$dzDots);    # Reloaded in Calc_qDots().
my $pDots;                              # Reloaded in Calc_pDots().

my ($iX0,$iY0,$iZ0);
my ($dXs,$dYs,$dZs,$dRs,$uXs,$uYs,$uZs);

my ($uLineXs,$uLineYs,$uLineZs);                # Reloaded in Calc_dQs()
my ($lineStretches,$lineStrains,$tautSegs);     # Reloaded in Calc_dQs().


sub Init_DynamSlices {
    
    ## Initialize counts, indices and useful slices of the dynamical variables.
    
    PrintSeparator ("Setting up the dynamical slices",3);
    if ($verbose>=3){pq($Dynams0)};
    
    
    $nSegs      = $numSegs;
    
    $iX0        = 0;
    $iY0        = $nSegs;
    $iZ0        = 2*$nSegs;
    $nQs        = 3*$nSegs;

    $nCGs       = $nSegs + 1;     # Includes and extra CG for the fly quasi-segment.
    $nCGQs      = 3*$nCGs;
    
    
    $nRodNodes  = $numRodNodes;
    $nRodSegs   = $numRodNodes-1;
    
    #pq($numLineNodes);
    $nLineNodes = $numLineNodes;  # Nodes outboard of the rod tip node.  The cg for each of these is inboard of the node.  However, the last node also is the location of an extra quasi-segment that represents the mass of the fly.
    
    $nqs        = 3*$nSegs;

    if ($verbose>=3){pq($nRodNodes,$nLineNodes,$nSegs,$nQs,$nCGs,$nCGQs,$nqs)}
    
    $dynams     = $Dynams0->copy->flat;    # Initialize our dynamical variables, reloaded at the beginning of DE().
    
    if ($dynams->nelem != 2*$nqs){die "ERROR: size mismatch with \$Dynams0.\n"}

    $dynamDots  = zeros($dynams);   # Set as output of DE().

    $idx0       = 0;
    $idy0       = $idx0+$nSegs;
    $idz0       = $idy0+$nSegs;
    if (DEBUG and $verbose>=4){pq($idx0,$idy0,$idz0)}
    
    $qs         = $dynams(0:$nqs-1);
    if ($verbose>=3){pq($dynams,$qs)}
    
    $dxs        = $qs(0:$idy0-1);
    $dys        = $qs($idy0:$idz0-1);
    $dzs        = $qs($idz0:-1);
    
    $ps         = $dynams($nqs:-1);
    if ($verbose>=3){pq($ps)}
    
    # Only possibly used in report:
    $dxps       = $ps(0:$idy0-1);
    $dyps       = $ps($idy0:$idz0-1);
    $dzps       = $ps($idz0:-1);
 
    $qDots      = zeros($qs);
        # Correctly initialized for empty loaded state, unused otherwise until reloaded in Calc_qDots().
    
    $dxDots     = $qDots($idx0:$idy0-1);
    $dyDots     = $qDots($idy0:$idz0-1);
    $dzDots     = $qDots($idz0:-1);

    ($drs,$uXs,$uYs,$uZs) = map {zeros($nSegs)} (0..3);
    $uLineXs       = $uXs($nRodSegs:-1);
    $uLineYs       = $uYs($nRodSegs:-1);
    $uLineZs       = $uZs($nRodSegs:-1);
    
    $pDots  = zeros($ps);
}


my ($dXs_dqs_extended,$dYs_dqs_extended,$dZs_dqs_extended);
my ($d2CGQs_d2thetas,$d2CGQs_d2phis,$dCGQs_dqs,$dQs_dqs);
my $extCGVs;
my ($CGQDots,$VXCGs,$VYCGs,$VZCGs);



sub Init_HelperPDLs {
    
    ## Initialize pdls that will be referenced by slices.
    
    PrintSeparator("Initializing helper PDLs",3);

    # Storage for  $dQs_dqs extended to enable interpolating for cgs partials:
    
    $dXs_dqs_extended       = zeros($nqs,$nSegs+2);
    $dYs_dqs_extended       = zeros($nqs,$nSegs+2);
    $dZs_dqs_extended       = zeros($nqs,$nSegs+2);
    # Plus 1 for the fly, and plus one more for averaging.
        # Ditto.
    
    # Storage for the nodes partials:
    $dQs_dqs                = zeros($nqs,$nQs);
   
    # Storage for the cgs partials:
    $dCGQs_dqs              = zeros($nqs,$nCGQs);
    $extCGVs                = zeros($nCGQs);
    
    # WARNING and FEATURE:  dummy acts like slice, and changes when the original does!  I make use of this in AdjustFirstSeg_STRIPPING().
    $CGQMassesDummy1        = $CGQMasses->dummy(1,$nqs);
    
    $CGQDots                = zeros(3*$nCGs);
}



my ($dXs_dqs,$dYs_dqs,$dZs_dqs);

sub Init_HelperSlices {
    
    PrintSeparator("Initializing helper slices",3);
    
    # Shorthand for the nodal partials:
    $dXs_dqs    = $dXs_dqs_extended(:,1:$nSegs);
    $dYs_dqs    = $dYs_dqs_extended(:,1:$nSegs);
    $dZs_dqs    = $dZs_dqs_extended(:,1:$nSegs);
    
    $VXCGs      = $CGQDots(0:$nCGs-1);
    $VYCGs      = $CGQDots($nCGs:2*$nCGs-1);
    $VZCGs      = $CGQDots(2*$nCGs:-1);

 
    if ($verbose>=3){pqInfo($dXs_dqs,$dYs_dqs,$dZs_dqs)}
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

my $stripCutoff = 0.0001;    # Inches.

sub AdjustFirstSeg_STRIPPING { use constant V_AdjustFirstSeg_STRIPPING => 0;
    my ($t) = @_;
    
    #pq($segLens,$lineSegLens,$segWts,$CGWts,$CGQMasses,$CGBuoys);
    
    
    my $stripNomLen = $lineSeg0LenFixed - ($t-$thisSegStartT)*$stripRate;
    #if ($stripNomLen < $stripCutoff){$stripNomLen = $stripCutoff}
    if ($stripNomLen < $stripCutoff){return}  # Don't make any more changes in this seg.
    if ($verbose>=3){pq($lineSeg0LenFixed,$stripNomLen)}
    
    #if ($stripNomLen < $stripCutoff){return 0}
    
    #$segLens(0)         .= $stripNomLen;
    $lineSegLens(0)     .= $stripNomLen;
        # This is a slice of $segLens, so 2-way adjustment takes care of that too.
    
    my $stripFract      = $stripNomLen/$lineSeg0LenFixed;

    my $stripWt         = $line0SegWtFixed * $stripFract;
    $segWts(0)              .= $stripWt;
    # At least approximately right.
    $CGWts(0)               .= $stripWt;
    $CGQMasses(0)           .= $massFactor*$stripWt;
    $CGQMasses($nCGs)       .= $massFactor*$stripWt;
    $CGQMasses(2*$nCGs)     .= $massFactor*$stripWt;
    
    
    #$segCGDiams($idx0)      .= ??      For now, leave this unchanged.
    my $stripBuoy   = $line0SegBuoyFixed(0) * $stripFract;
    $CGBuoys($idx0) .= $stripBuoy;
    
    # The original Ks and Cs include segLen in the denominator.
    $lineSegKs(0)       .= $line0SegKFixed / $stripFract;
    $lineSegCs(0)       .= $line0SegCFixed / $stripFract;
    if ($verbose>=3){pq($lineSegKs,$lineSegCs)}
    
    # For now, will leave cg unchanged.
    if (V_AdjustFirstSeg_STRIPPING and $verbose>=4){pq($stripWt,$stripBuoy)}
    #pq($segLens,$lineSegLens,$segWts,$CGWts,$CGQMasses$CGBuoys);
    
}


sub AdjustTrack_STRIPPING { use constant V_AdjustTrack_STRIPPING => 0;
    my ($t) = @_;
    
    ### Doesn't seem to be necessary since $stripCutoff = 0.0001;    # Inches. works in preliminary tests.  Cutoff = 0, however, blows up, as expected.
}


sub Calc_dQs { use constant V_Calc_dQs => 0;
    # Pre-reqs: $qs set, and if $numRodSegs, Calc_Driver().
    
    ## Calculate the rod and line segments as cartesian vectors from the dynamical variables.  In this formulation, there is not much to do, since the $dXs = $dxs, etc, so only the $drs are loaded here, and the cartesian unit vectors.

    #pq($dxs,$dys,$dzs);

    $drs  .= sqrt($dxs**2 + $dys**2 + $dzs**2);
    # Line dxs, dys were automatically updated when qs was loaded.
    
    $lineStretches  = ($drs($nRodSegs:-1)-$lineSegLens)->flat;
    $lineStrains    = ($lineStretches/$lineSegLens)->flat;
    $tautSegs       = $lineStrains >= 0;
    if (DEBUG and $verbose>=3){pq($drs,$lineStretches,$lineStrains,$tautSegs)}


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
    
    #    return ($dXs,$dYs,$dZs);
}

my ($driverTheta,$driverPhi,$driverX,$driverY,$driverZ);
my ($driverThetaDot,$driverPhiDot,$driverXDot,$driverYDot,$driverZDot);


sub Calc_Driver { use constant V_Calc_Driver => 0;
    my ($t) = @_;   # $t is a PERL scalar.
    
    if ($t < $driverStartTime) {$t = $driverStartTime}
    if ($t > $driverEndTime) {$t = $driverEndTime}
    
    
    ($driverTheta,$driverPhi,$driverX,$driverY,$driverZ) = map {0} (0..4);
    
    if ($numRodSegs){
        $driverTheta    = ($numRodSegs)?$driverThetaSpline->evaluate($t) + $driverOffsetTheta:0;
        $driverPhi      = ($numRodSegs)?$driverPhiSpline->evaluate($t) + $driverOffsetPhi:0;
    }
    if ($numLineSegs){
        $driverX        = $driverXSpline->evaluate($t);
        $driverY        = $driverYSpline->evaluate($t);
        $driverZ        = $driverZSpline->evaluate($t);
    }
    
    ($driverThetaDot,$driverPhiDot,$driverXDot,$driverYDot,$driverZDot) = map {0} (0..4);
    # Critical to make sure that the velocity is zero if outside the drive time range.
    
    if ($t > $driverStartTime and $t < $driverEndTime){
        
        my $dt = ($t <= ($driverStartTime+$driverEndTime)/2) ? 0.001 : -0.001;
        $dt *= $driverEndTime - $driverStartTime;     # Must be small compared to changes in the splines.
        
        if ($numRodSegs){
            $driverThetaDot = $driverThetaSpline->evaluate($t+$dt) + $driverOffsetTheta;
            $driverThetaDot = ($driverThetaDot-$driverTheta)/$dt;
            
            $driverPhiDot = $driverPhiSpline->evaluate($t+$dt) + $driverOffsetPhi;
            $driverPhiDot = ($driverPhiDot-$driverPhi)/$dt;
            
        }
        if ($numLineSegs){
            
            $driverXDot = $driverXSpline->evaluate($t+$dt);
            $driverXDot = ($driverXDot-$driverX)/$dt;
            
            $driverYDot = $driverYSpline->evaluate($t+$dt);
            $driverYDot = ($driverYDot-$driverY)/$dt;
            
            $driverZDot = $driverZSpline->evaluate($t+$dt);
            $driverZDot = ($driverZDot-$driverZ)/$dt;
        }
    }
    
    if (DEBUG and V_Calc_Driver and $verbose>=4){
        print "Calc_Driver($t): hTheta=$driverTheta, hPhi=$driverPhi, hX=$driverX, hY=$driverY, hZ=$driverZ, hThetaD=$driverThetaDot, hPhidD=$driverPhiDot, hXD=$driverXDot, hYD=$driverYDot, hZD=$driverZDot\n";
    }
    
    # Return values (but not derivatives) are used only in the calling program:
    return ($driverTheta,$driverPhi,$driverX,$driverY,$driverZ);
    #return ($driverTheta,$driverPhi,$driverX,$driverY,$driverZ,$driverThetaDot,$driverPhiDot,$driverXDot,$driverYDot,$driverZDot);
}


my ($CGXs,$CGYs,$CGZs);

# Used only in computing fluid drag.
sub Calc_CGQs { use constant V_Calc_CGQs => 0;
    # Pre-reqs:  Calc_Driver() and Calc_dQs().
    
    ## Compute the cartesian coordinates Xs, Ys and Zs of all the NODES.
    
    if ($numRodSegs){die "Not yet implemented in 3D.\n"}

    my $dxs = pdl($driverX)->glue(0,$dxs);
    my $dys = pdl($driverY)->glue(0,$dys);
    my $dzs = pdl($driverZ)->glue(0,$dzs);
    
    my $Xs = cumusumover($dxs);
    my $Ys = cumusumover($dys);
    my $Zs = cumusumover($dzs);
    
    my $extendedXs = $Xs->glue(0,$Xs(-1));
    my $extendedYs = $Ys->glue(0,$Ys(-1));
    my $extendedZs = $Zs->glue(0,$Zs(-1));
    
    $CGXs = (1-$CGs)*$extendedXs(0:-2)+$CGs*$extendedXs(1:-1);
    $CGYs = (1-$CGs)*$extendedYs(0:-2)+$CGs*$extendedYs(1:-1);
    $CGZs = (1-$CGs)*$extendedZs(0:-2)+$CGs*$extendedZs(1:-1);
    
    if (V_Calc_CGQs and $verbose>=3){print "\nCalc_CGQs --- \n";pq($Xs,$Ys,$Zs,$CGs,$CGXs,$CGYs,$CGZs)}
    #return ($CGXs,$CGYs,$CGZs);
}



sub Calc_CartesianPartials { use constant V_Calc_CartesianPartials => 0;
    # Pre-reqs: $qs set.
    
    ## The returns are all constant during the integration, so this need only be called during init.
    
    ## Compute first partials of the nodal cartesian coordinates with respect to the dynamical variables.  NOTE that the second partials are not needed in this case.
    
    # the partial of the Xs wrt x0 (=X0) is 1 and that of Ys is zero.
    # similarly for partials wrt to y0.  = so (  ones($nSegs),zeros($nSegs), etc.
    
    # $holding is always 0 here.

    #pq($dXs_dqs_extended,$dYs_dqs_extended);
    $dXs_dqs_extended(0:$idy0-1,1:-1)       .= $lowerTriPlus;
    $dYs_dqs_extended($idy0:$idz0-1,1:-1)   .= $lowerTriPlus;
    $dZs_dqs_extended($idz0:0-1,1:-1)       .= $lowerTriPlus;
    # (+)1 because of the zeros first row in extended.  The size of $lowerTriPlus was set properly when it was created.
    #pq($dXs_dqs_extended,$dYs_dqs_extended);
    
    #pq($dXs_dqs,$dYs_dqs,$dZs_dqs);    # These are just slices of the extended versions.
    
    
    $dQs_dqs .= $dXs_dqs->glue(1,$dYs_dqs)->glue(1,$dZs_dqs);
    # If you're going to assign everything, might as well glue.  I can imagine an implementation that does this just as efficiently.
    #$dQs_dqs(:,0:$nSegs-1)    .= $dXs_dqs;
    #$dQs_dqs(:,$nSegs:-1)     .= $dYs_dqs;
    #pq($dQs_dqs);
    
    # Interpolate:
    my $CGs_tr = $CGs->transpose;
    
    #### NOTE that while the CGs enter, the actual segLens do not.  This means, among other things, that this function does not have be called in DE, even when stripping.
    
    $dCGQs_dqs .=
    ((1-$CGs_tr)*$dXs_dqs_extended(:,0:-2) + $CGs_tr*$dXs_dqs_extended(:,1:-1))
    ->glue(1,(1-$CGs_tr)*$dYs_dqs_extended(:,0:-2) + $CGs_tr*$dYs_dqs_extended(:,1:-1))
    ->glue(1,(1-$CGs_tr)*$dZs_dqs_extended(:,0:-2) + $CGs_tr*$dZs_dqs_extended(:,1:-1));
    #pq($dCGQs_dqs);
    
    if (V_Calc_CartesianPartials and $verbose>=3){print "In calc partials: ";pq($dCGQs_dqs,$dQs_dqs)}

    #return ($dCGQs_dqs,$dQs_dqs);
}



sub Calc_ExtCGVs { use constant V_Calc_ExtCGVs => 0;
    # Pre-reqs:  Calc_Driver(), and if $numRodSegs, Calc_CartesianPartials().
    
    ## External velocity is nodal motion induced by driver motion, path and orientation, but not by the bending at the zero node.  NOTE that the part of the external V's contributed by the change in driver direction is gotten from the first column of the dQs_dqs matrix (which is the same as the first column of the $dQs_dthetas matrix), in just the same way that the internal contribution of the bending of the 0 node is.
    
    if (DEBUG and V_Calc_ExtCGVs and $verbose>=4){print "\nCalc_ExtVs ----\n"}
    #pq($driverXDot,$driverYDot,$driverThetaDot)}
    
    $extCGVs .= (   $driverXDot*ones($nCGs))
                    ->glue(0,$driverYDot*ones($nCGs))
                    ->glue(0,$driverZDot*ones($nCGs));
    
    # driverThetaDot only comes into play if there is at least one rod segment.
    if ($numRodSegs){
        die "Not yet implemented in 3D.\n";
        
        $extCGVs += $driverThetaDot * $dCGQs_dqs(0,:)->flat;
    }
    #!!! the adjustment to $dCGQs_dqs should do this automatically!

    if (V_Calc_ExtCGVs and $verbose>=3){pq $extCGVs}
    #return $extCGVs;
}


my $dMCGQs_dqs_Tr;
my $inv;

sub Calc_KE_Inverse { use constant V_Calc_KE_Inverse => 0;
    # Pre-reqs:  $ps set, Calc_CartesianPartials() or Calc_CartesianPartials_NoRodSegs().  If not$numRodSegs, this need be called only once, during init.
    
    ## Solve for qDots in terms of ps from the definition of the conjugate momenta as the partial derivatives of the kinetic energy with respect to qDots.  We evaluate the matrix equation      qDots = ((Dtr*bigM*D)inv)*(ps - Dtr*bigM*Vext).
    
    # !!!  By definition, p = ∂/∂qDot (Lagranian) = ∂/∂qDot (KE) - 0 = ∂/∂qDot (KE).  Thus, this calculation is not affected by the definition of the Hamiltonian as Hamiltonian = p*qDot - Lagrangian, which comes later.  However, the pure mathematics of the Legendre transformation then gives qDot = ∂/∂p (H).
 
    ## !!!! For line only, $inv need be computed only once!!!!!
    
    if (DEBUG and V_Calc_KE_Inverse and $verbose>=4){print "\nCalc_qDots ---- \n"}
    
    $dMCGQs_dqs_Tr = $CGQMassesDummy1*($dCGQs_dqs->transpose);
    if (DEBUG and V_Calc_KE_Inverse and $verbose>=4){pq $dMCGQs_dqs_Tr}

    my $fwd = $dMCGQs_dqs_Tr x $dCGQs_dqs;
    if (DEBUG and V_Calc_KE_Inverse and $verbose>=3){pq $fwd}
    
    $inv = $fwd->inv;
    if (DEBUG and V_Calc_KE_Inverse and $verbose>=4){pq $inv}
    
    if (DEBUG and V_Calc_KE_Inverse and $verbose>=5){
        my $dd = det($inv);
        my $test = $inv x $fwd;
        pq($dd,$test);
    }
    
    # return($dMCGQs_dqs_Tr,$inv);
}


sub Calc_qDots { use constant V_Calc_qDots => 0;
    # Pre-reqs:  $ps set.  If not$numRodSegs, Calc_KE_Inverse() need be called only once, during init.
    
    if ($numRodSegs){Calc_KE_Inverse()}
    # Else, need do this only once, on startup.
    
    my $ext_ps_Tr = $dMCGQs_dqs_Tr x $extCGVs->transpose;
    my $ps_Tr = $ps->transpose;
    my $pDiffs_Tr = $ps_Tr - $ext_ps_Tr;
    
    if (DEBUG and V_Calc_qDots and $verbose>=3){
        my $tMat = $ps_Tr->glue(0,$ext_ps_Tr)->glue(0,$pDiffs_Tr);
        print "cols(ps,ext_ps,p_diffs)=$tMat\n";
    }
    
    $qDots .= ($inv x $pDiffs_Tr)->flat;
    
    if (DEBUG and V_Calc_qDots and $verbose>=4){pq $qDots}
    
    # return $qDots;
}




sub Calc_CGQDots { use constant V_Calc_CGQDots => 0;
    # Pre-reqs:  Calc_ExtCGVs() and Calc_CartesianPartials() or Calc_CartesianPartials_NoRodSegs(), and Calc_qDots().
    
    if (V_Calc_CGQDots and $verbose>=3){print "\nCalc_CGQDots ----\n"}
    
    my $intCGVs = ($dCGQs_dqs x $qDots->transpose)->flat;
    #pq($intCGVs,$holding);
    
    $CGQDots .= $extCGVs + $intCGVs;
    
    if (V_Calc_CGQDots and $verbose>=3){pq $CGQDots}
    # return $CGQDots;
}


=begin comment
my $pDotsKE;

sub Calc_pDotsKE { use constant V_Calc_pDotsKE => 0;
    # Pre-reqs: Calc_qDots().
    
    die "Supposed to be unneeded in new formulation.\n";
    
    ## Compute the kinetic energy's contribution to pDots.
    
    # !!! Using the correct, general definition of Hamiltonian = p*qDot - Lagrangian, where L = cartesian KE - PE, we get the contribution to pDot is -∂/∂q (H) = +∂/∂q (KE) - ∂/∂q (PE) since there is no dependence of p*qDot on q.  Thus this function needs to return the plus sign!!!  All the other contributions to pDot come from the PE, and get a minus sign.
    
    # BUT, worry about whether the frictional terms belong in KE or PE.
    
    # NOTE that because of the very particular form of the LINE dynamical variables (differences of adjacent node cartesian coordinates), the KINETIC energy does not depend on these variables (dxs, dys) themselves, but only on their derivatives (dxDots, dyDots).
    
    # Thus, from the Hamiltonian formulation, we have NO CONTRIBUTION from the kinetic energy to the time derivatives of the conjugate momenta (pDots) corresponding to the LINE variables.  Consequently this function returns pDots only for the rod variables (thetas).  Of course, because of line elasticity and gravity, the line variables DO supply a POTENTIAL ENERGY contribution to the pDots
    
    if (0 and $numRodSegs){
        
        die "Not yet implemented in 3D\n";
    
        if (DEBUG and V_Calc_pDotsKE and $verbose>=4){print "\nCalc_pDotsKE ----\n"}
        #die "make sure I get the right sign here  Should be negative of dKE/dq, and include ext v's properly";
        
        # Figure the cartesian momentum:
        my $Ps = $CGQMasses * $CGQDots;
        # pq($Ps);
       # pqInfo($Ps);
        #    pq($qDots);
        
        my $WsMat = zeros($numRodNodes,2*$nCGs);
        
        for (my $ii=0;$ii<$numRodNodes;$ii++) {
            $WsMat($ii,:) .= $d2CGQs_d2thetas(:,:,$ii)->reshape($nThetas,2*$nCGs)
            x $dthetaDots->transpose;       # Squeeze below unsafe if 1 rod seg.
        }
        #pq($WsMat);
        $pDotsKE = ($Ps x $WsMat)->flat;       #--
        ### 17/09/02 I added minus sign here, since pDot = - ∂KE/∂q.  On 17/09/05 changed back since I decided that was wrong.  See comment above.
        
        if (V_Calc_pDotsKE and $verbose>=3){
            my $tMat = $Ps->transpose->glue(0,$WsMat);
            print "cols(Ps,Ws)=$tMat\n\n";
        }
        
        if (DEBUG and V_Calc_pDotsKE and $verbose>=5){pq $pDotsKE}
        # return $pDotsKE;
    }
}
=end comment
=cut

my ($pDotsRodK,$pDotsRodC);

sub Calc_pDotsRodMaterial { use constant V_Calc_pDotsRodMaterial => 1;
    
    die " Not yet implemented in 3D.\n";
    ## Components of the derivative of potential from stretching OR compressing the seg, plus that of potential from bending at the node in 3D.
    
    # will need both $rodKsNoTipBending and $rodKsNoTipTension, different leveraging of the fiber youngs modulus.
    
    # Plus, worry about whether my treatment of C is right.  Or, should it be in the calc of ps from the qDots?  Formally, there, but maybe this is equivalent.  In any case, a bit of C stabilizes the solver.
    
}


my ($pDotsLineK,$pDotsLineC);

sub Calc_pDotsLineMaterial { use constant V_Calc_pDotsLineMaterial => 1;
    # Uses ($qs,$qDots) = @_;
    # Calc_dQs() must be called first.
    
    ## Enforce line segment constraint as a one-sided, damped harmonic oscillator.
    
    if (!$numLineSegs){return (zeros(0),zeros(0))};
    
    if (DEBUG and V_Calc_pDotsLineMaterial and $verbose>=4){print "\nCalc_pDotsLineMaterial ----\n"}
    
    # $lineSegKs already has $segLens built into the denominator, so wants to be multiplied by stretches, not strains.
    
    my $lineForceTension = -SmoothOnset($lineStretches,0,$smallStretch)*$lineSegKs;
    
    #pq($lineStrains,$smoothTauts,$lineForceTension);
    
    # Figure the RATE of stretching:
    my $lineStretchDots = ($dxDots*$uLineXs+$dyDots*$uLineYs+$dzDots*$uLineZs);
    if (DEBUG and V_Calc_pDotsLineMaterial and $verbose>=4){pq($lineStretchDots)}
    
    # Use LINEAR velocity damping, since the stretches should be slow relative to the cartesian line velocities. BUT, is this really true?:
    #    my $lineForceDamping = -$tautSegs*$rDotsLine*$lineSegCs;
    #my $lineForceDamping = -$smoothTauts*$rDotsLine*$lineSegCs;
    my $smoothTauts         = 1-SmoothChar($lineStrains,0,$smallStrain);
    if (DEBUG and V_Calc_pDotsLineMaterial and $verbose>=4){pq($smoothTauts)}

    my $lineForceDamping    = -$lineStretchDots*$lineSegCs*$smoothTauts;
    #
    if ($verbose>=3){pq($lineForceTension,$lineForceDamping)}
    
    # The forces act only along the segment tangent directions:
    $pDotsLineK  = ($lineForceTension*$uLineXs)->glue(0,$lineForceTension*$uLineYs)->glue(0,$lineForceTension*$uLineZs);
    $pDotsLineC  = ($lineForceDamping*$uLineXs)->glue(0,$lineForceDamping*$uLineYs)->glue(0,$lineForceDamping*$uLineZs);
    
    #return ($pDotsLineK,$pDotsLineC,$lineForceTension(0));
}



my ($XDiffHeld,$YDiffHeld,$ZDiffHeld,$RDiffHeld,$stretchHeld,$strainHeld,$tautHeld);
my ($XTip0,$YTip0,$ZTip0);

sub Calc_pDotsTip_HOLD { use constant V_Calc_pDotsTip_HOLD => 0;
    my ($t,$tFract) = @_;   # $t is a PERL scalar.
    
    ## For times less than start release, make the tension force on the last line segment (with its original, small, spring constant) depend on the distance between the next-to-last node and the fixed tip point.  Implement as cartesian force acting on that node. The original (dxs(-1),dys(-1) are not dynamical variables in this case.
    
    # For times between start and end release, call Calc_pDotsTip_SOFT_RELEASE() instead.
    
    if ($numRodSegs){die "ERROR:  Rod not yet implemented.\n"}
    
    my $pDots_HOLD = zeros($ps);
    if ($tFract!=1){ return $pDots_HOLD}
    
    if (V_Calc_pDotsTip_HOLD and $verbose>=3){print "Calc_pDotsTipHold: t=$t,ts=$tipReleaseStartTime, te=$tipReleaseEndTime, fract=$tFract\n"}
    
    # Must be sum over everything, since original last seg not dynamic, and so is not included in the (dXs,dYs) computed in holding mode.
    my $XDynamLast = $driverX + sumover($dXs);
    my $YDynamLast = $driverY + sumover($dYs);
    my $ZDynamLast = $driverZ + sumover($dZs);
    if ($verbose>=3){pq($XDynamLast,$YDynamLast,$XTip0,$YTip0)}
   
    $XDiffHeld  = $XTip0-$XDynamLast;
    $YDiffHeld  = $YTip0-$YDynamLast;
    $ZDiffHeld  = $ZTip0-$ZDynamLast;
    $RDiffHeld  = sqrt($XDiffHeld**2 + $YDiffHeld**2 + $ZDiffHeld**2);

    
    $stretchHeld     = $RDiffHeld-$HeldSegLen;
    $strainHeld      = $stretchHeld/$HeldSegLen;
    $tautHeld        = $strainHeld >= 0;
    
    #    pq($stretchHeld,$strainHeld,$tautHeld);
 
    if ($tautHeld){
        $pDots_HOLD = $HeldSegK * $stretchHeld *
                                (   ($XDiffHeld/$RDiffHeld) * $dQs_dqs(:,$iY0-1)->flat +
                                    ($YDiffHeld/$RDiffHeld) * $dQs_dqs(:,$iZ0-1)->flat +
                                    ($ZDiffHeld/$RDiffHeld) * $dQs_dqs(:,-1)->flat );
        # Sic. $dQs_dqs since we want contribution from a node.  Plus sign because the force points toward the fly from the previous node.
    }
    
    ### ??? shouldn't there be a contribution from $HeldSegC??
    
    if (V_Calc_pDotsTip_HOLD and $verbose>=3){pq($pDots_HOLD)}

    return $pDots_HOLD;
}


my ($tKSoft,$XDiffSoft,$YDiffSoft,$ZDiffSoft,$RDiffSoft,$stretchSoft);

sub Calc_pDotsTip_SOFT_RELEASE { use constant V_Calc_pDotsTip_SOFT_RELEASE => 0;
    my ($t,$tFract) = @_;   # $t is a PERL scalar.
    
    ## Large cartesian force before release start, no force after release end, applied to the tip node.
    if ($numRodSegs){die "ERROR:  Rod not yet implemented.\n"}
    
    my $pDots_SOFT_RELEASE = zeros(0);
    if ($tFract>=1 or $tFract<=0){ return $pDots_SOFT_RELEASE}
    
    if (V_Calc_pDotsTip_SOFT_RELEASE and $verbose>=3){print "Calc_pDotsTip_SOFT_RELEASE: t=$t,ts=$tipReleaseStartTime, te=$tipReleaseEndTime, fract=$tFract\n"}
    
    $tKSoft = $KSoftRelease * $tFract;
    ## The contribution to the potential energy from forces holding the fly in place affect all the dynamical variables, since a change in to any of them holding the rest fixed moves the fly.
    #my $tipEnergy = $tKSoft/2 * (($Xs(-1)-$XTip0)**2 + ($Ys(-1)-$YTip0)**2);
    # -dtipEnergyX/ddynvar = -$tKSoft * ($Xs(-1)-$XTip0) * dXs(-1)/ddynvar.
    
    my $XTip = $driverX + sumover($dXs);
    my $YTip = $driverY + sumover($dYs);
    my $ZTip = $driverZ + sumover($dZs);
    if ($verbose>=3){pq($XTip,$YTip,$ZTip,$XTip0,$YTip0,$ZTip0)}
    
    $XDiffSoft  = $XTip0-$XTip;
    $YDiffSoft  = $YTip0-$YTip;
    $ZDiffSoft  = $ZTip0-$ZTip;
    $RDiffSoft  = sqrt($XDiffSoft**2 + $YDiffSoft**2 + $ZDiffSoft**2);
    
    $stretchSoft     = $RDiffSoft;
    
    $pDots_SOFT_RELEASE = $tKSoft * $stretchSoft *
        (   ($XDiffSoft/$RDiffSoft) * $dQs_dqs(:,$iY0-1)->flat +
            ($YDiffSoft/$RDiffSoft) * $dQs_dqs(:,$iZ0-1)->flat +
            ($ZDiffSoft/$RDiffSoft) * $dQs_dqs(:,-1)->flat);
        # Sic. $dQs_dqs since we want contribution from a node.
    
    if (V_Calc_pDotsTip_SOFT_RELEASE and $verbose>=3){pq($pDots_SOFT_RELEASE)}
    return $pDots_SOFT_RELEASE;
}



# =============  New, water drag

my $isSubmergedMult;    # Include smooth transition in the water surface layer.

sub Calc_VerticalProfile { use constant V_Calc_VerticalProfile => 0;
    my ($CGZs,$typeStr,$bottomDepthFt,$surfaceVelFtPerSec,$halfVelThicknessFt,$surfaceLayerThicknessIn,$plot) = @_;
    
    # To work both in air and water.  Vel's above surface (y=0) (air) are zero, below the surface from the water profile.  Except, I make a smooth transition at the water surface over the height of the surface layer thickness, given by the $isSubmergedMult returned.  This will then be used in setting the buoyancy contribution to pDots, which makes the integrator much happier.
    
    my $D   = $bottomDepthFt*12;         # inches
    my $v0  = $surfaceVelFtPerSec*12;   # inches/sec
    my $H   = $halfVelThicknessFt*12;   # inches
    
    # Set any pos CGYs to 0 (return them to the water surface) and any less than -depth to -depth.
    $CGZs = $CGZs->copy;    # Isolate pdl.
    my $ok = $D+$CGZs>=0;   # Above the bottom
    $CGZs = $ok*$CGZs+(1-$ok)*(-$D);    # If below the bottom, place at bottom
    
    if (any(!$ok)){
        $DE_status = -2;
        $DE_errMsg  = "ERROR:  Detected a CG below the water bottom.  CANNOT PROCEED.  Try increasing bottom depth or stream velocity, or lighten the line components.$vs";
    }
    
    $isSubmergedMult = $CGZs <= 0;
    
    my $vels;
    if ($v0){
        switch ($typeStr) {
            
            case "const" {
                $vels = $v0 * ones($CGZs);
            }
            case "lin" {
                my $a = $D/$v0;
                $vels = ($D+$CGZs)/$a;
            }
            case "exp" {
               # y = ae**kv0, y= a+D+1+Y (Yneg). a=H**2/(D-2H), k = ln((D+a)/a)/v0.
                my $a = $H**2/($D-2*$H);
                my $k = log( ($D+$a)/$a )/$v0;
                $vels = log( ($a+$D+$CGZs)/$a )/$k;
                # CGYs are all non-pos, 0 at the surface.  Depth pos.
            }
        }
    }else{
        $vels = zeros($CGZs);
    }
    
    # If not submerged, make velocity zero except in the surface layer
    $isSubmergedMult = SmoothChar($CGZs,0,$surfaceLayerThicknessIn);
    #pq($surfaceMults);
    $vels *= $isSubmergedMult;
    #pq($vels);
    
    
    if (defined($plot) and $plot){
        my $plotMat = ($CGZs->glue(1,$vels))->transpose;
        
        PlotMat($plotMat(-1:0,:),0,"Velocity(in/sec) vs Depth(in)");
        #PlotMat($plotMat,0,"Depth(in) vs Velocity(in/sec)");
    }
    
    if (V_Calc_VerticalProfile and $verbose>=3){pq($CGZs,$vels,$isSubmergedMult)}
    return ($vels,$isSubmergedMult);
}


sub Calc_HorizontalProfile { use constant V_Calc_HorizontalProfile => 0;
    my ($CGYs,$halfWidthFt,$exponent,$plot) = @_;
    
    
    my $horizMults;
    if ($exponent >= 2){

        my $Ys  = abs($CGYs->copy);    # Inches.
        $Ys     /= $halfWidthFt*12;
       
        #pq($Ys);
        $horizMults = 1/($Ys**$exponent + 1);
        

    } else {
        $horizMults = ones($CGYs);
    }
    
    if (defined($plot) and $plot){
        my $plotMat = ($CGYs->glue(1,$horizMults))->transpose;
        
        PlotMat($plotMat,0,"Horizontal Vel Multiplier vs Distance(in)");
    }
    
    if (V_Calc_HorizontalProfile and $verbose>=3){pq($CGYs,$horizMults)}
    return ($horizMults);
}


sub Calc_SegDragForces { use constant V_Calc_SegDragForces => 0;
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
    if (DEBUG and V_Calc_SegDragForces and $verbose>=4){print "CHECK THIS: At least temporarily, am bounding RE's away from zero.\n"}
    my $minRE = 0.01;
    my $ok = $REs > $minRE;
    $REs = $ok*$REs + (1-$ok)*$minRE;
    
    my $CDrags  = $mult*$REs**$power + $min;
    my $FDrags  = $CDrags*(0.5*$fluidBlubsPerIn3*($speeds**2)*$segCGDiams*$segLens);
    # Unit length implicit.
    
    # Fix any nans that appeared:
    #$FDrags = ReplaceNonfiniteValues($FDrags,0);
    
    if (V_Calc_SegDragForces and $verbose>=3){pq($type,$REs,$CDrags,$FDrags);print "\n"}
    
    return $FDrags;
}



my $CGForcesDrag;  # For reporting
my ($VXs,$VYs,$VAs,$VNs,$FAs,$FNs,$FXs,$FYs);    # For possible reporting.

sub Calc_DragsCG { use constant V_Calc_DragsCG => 0;
    # Pre-reqs: Calc_dQs(), Calc_CGQs(), and Calc_CGQDots().
    
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
    
    
    if (DEBUG and V_Calc_DragsCG and $verbose>=4){print "\nCalcDragsCG ----\n"}
    
    Calc_CGQs();    # Used only here, nowhere else.
    
    # Get the segment-centered relative velocities:
    if (DEBUG and V_Calc_DragsCG and $verbose>=4){pq($VXCGs,$VYCGs,$VZCGs)}
    
    my $relVXCGs = -$VXCGs->copy;
    my $relVYCGs = -$VYCGs->copy;
    my $relVZCGs = -$VZCGs->copy;
    
    if (DEBUG and $verbose>=4){pq($relVXCGs,$CGZs)}
    
    if ($airOnly){
        $isSubmergedMult = zeros($CGZs);
    }else{
        # Need modify only vx, since fluid vel is parallel to the X-direction.
        my $fluidVXCGs;
        ($fluidVXCGs,$isSubmergedMult) =
            Calc_VerticalProfile($CGZs,$profileStr,$bottomDepthFt,$surfaceVelFtPerSec,$halfVelThicknessFt,$surfaceLayerThicknessIn);
        
        if ($horizExponent >= 2){
            my $mults = Calc_HorizontalProfile($CGYs,$horizHalfWidthFt,$horizExponent);
            $fluidVXCGs *= $mults;
        }
        
        #pq($fluidVXCGs);
        
        $relVXCGs += $fluidVXCGs;
        if (DEBUG and V_Calc_DragsCG and $verbose>=4){pq($fluidVXCGs)}
    }
    if (DEBUG and V_Calc_DragsCG and $verbose>=4){pq($relVXCGs,$relVYCGs,$relVZCGs)}
    
    # Deal with the ordinary segment and fly pseudo-segment separately:
    my $segRelVXCGs = $relVXCGs(0:-2);
    my $segRelVYCGs = $relVYCGs(0:-2);
    my $segRelVZCGs = $relVZCGs(0:-2);
    
    my $flyRelVX   = $relVXCGs(-1);
    my $flyRelVY   = $relVYCGs(-1);
    my $flyRelVZ   = $relVZCGs(-1);
    if (DEBUG and $verbose>=4){pq($segRelVXCGs,$segRelVYCGs,$segRelVZCGs)}
    
    # Project to find the axial and normal (rotated CCW from axial) relative velocity components at the segment cgs:
    my $projAs  = $uXs*$segRelVXCGs + $uYs*$segRelVYCGs + $uZs*$segRelVZCGs;
    my $speedAs = abs($projAs);
    
    # Use Gram-Schmidt to find the normal relative velocity vectors:
    my $segRelVNXCGs    = $segRelVXCGs - $projAs*$uXs;
    my $segRelVNYCGs    = $segRelVYCGs - $projAs*$uYs;
    my $segRelVNZCGs    = $segRelVZCGs - $projAs*$uZs;
    
    my $speedNs = sqrt($segRelVNXCGs**2 +$segRelVNYCGs**2 +$segRelVNZCGs**2);
    my $nXs     = $segRelVNXCGs/$speedNs;
    my $nYs     = $segRelVNYCGs/$speedNs;
    my $nZs     = $segRelVNZCGs/$speedNs;
    
    # Replace any NaN's with zeros:
    my $ii = which(!$speedNs);
    if (!$ii->isempty){
        $nXs($ii) .= 0;
        $nYs($ii) .= 0;
        $nZs($ii) .= 0;
    }
    if (DEBUG and V_Calc_DragsCG and $verbose>=4){pq($nXs,$nYs,$nZs)}
    
    # Get the forces associated with the axial and normal speeds:
    my $segIsSubmergedMult = $isSubmergedMult(0:-2);

    if (DEBUG and V_Calc_DragsCG and $verbose>=4){pq($speedNs,$speedAs)}
   
    my $FNs = Calc_SegDragForces($speedNs,$segIsSubmergedMult,"normal",$segCGDiams,$segLens);
    my $FAs = Calc_SegDragForces($speedAs,$segIsSubmergedMult,"axial",$segCGDiams,$segLens);
    if (DEBUG and $verbose>=4){pq($FNs,$FAs)}
    
    
    # Add them component-wise to get the resultant cartesian forces. Drag forces point in the same direction as the relative velocities, hence the plus signs below:
    my $CGDragXs = $uXs*$FAs + $nXs*$FNs;
    my $CGDragYs = $uYs*$FAs + $nYs*$FNs;
    my $CGDragZs = $uZs*$FAs + $nZs*$FNs;

    #pq($CGDragXs,$CGDragYs,$CGDragZs);
    
    # We have computed axial and normal drags as if all the segments were taut.  Later I will modify these for the slack segements.  Of course, all the rod segments are taut.    if ($verbose>=3){pq($uXs,$uYs,$VAs,$VNs,$FAs,$FNs,$CGDragXs,$CGDragYs)}
    #if (DEBUG and $verbose>=4){Calc_Kiting($VNs,$VAs,$CGDragXs,$CGDragYs)}

    
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
    
    
    # Add the fly drag to the line (or if none, to the rod) tip node. No notion of axial or normal here:
    $CGDragXs = $CGDragXs->glue(0,zeros(1));
    $CGDragYs = $CGDragYs->glue(0,zeros(1));
    $CGDragZs = $CGDragZs->glue(0,zeros(1));
    
    my $flySpeed = sqrt($flyRelVX**2 + $flyRelVY**2 + $flyRelVZ**2);
    if (DEBUG and  V_Calc_DragsCG and $verbose>=3){pq($flyRelVX,$flyRelVY,$flyRelVY,$flySpeed)}
    
    if ($flySpeed){
        
        my $flyIsSubmerged  = $isSubmergedMult(-1);
        my $flyMultiplier   =
            Calc_SegDragForces($flySpeed,$flyIsSubmerged,"normal",$flyNomDiam,$flyNomLen);

        $CGDragXs(-1)  += $flyMultiplier*$flyRelVX/$flySpeed;
        $CGDragYs(-1)  += $flyMultiplier*$flyRelVY/$flySpeed;
        $CGDragZs(-1)  += $flyMultiplier*$flyRelVZ/$flySpeed;
    }
    
    if ($verbose>=3){pq($CGDragXs,$CGDragYs,$CGDragZs)}     # Always report forces.
    
    $CGForcesDrag = $CGDragXs->glue(0,$CGDragYs)->glue(0,$CGDragZs);
    if (DEBUG and V_Calc_DragsCG and $verbose>=4){pq($CGForcesDrag)}

    # return $CGForcesDrag;
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



#my $frictionAdjustFract = 0.1;
my $frictionAdjustFract = 1000000000;
my $frictionRatios = pdl(0); # 1 means no adjustment.


my ($pDots_NonVsFrict,$rodStaticError);   # For reporting.

sub Calc_pDots { use constant V_Calc_pDots => 0;
    my ($t) = @_;   # $t is a PERL scalar.
    
    ## Compute the change in the conjugate momenta due to the internal and cartesian forces.
    
    # To try to avoid sign errors, my convention for this function is that all contributions to $pDots are plus-equaled.  It is the job of each contributing calculator to get its own sign right.
    
    if (DEBUG and V_Calc_pDots and $verbose>=4){print "\nCalc_pDots ----\n"}

    $pDots  .= 0;
    
    # Compute contribution to pDots from the applied CG forces:
    my $CGNetAppliedForces = zeros($nCGQs);
    
    if ($calculateFluidDrag){

        Calc_DragsCG();    # Do this first so $isSubmergedMult is set:
        if (V_Calc_pDots and $verbose>=3){pq($CGForcesDrag,$isSubmergedMult)}
        $CGNetAppliedForces    .= $CGForcesDrag;
        
        my $CGForcesBuoyancy    = $gravity*$CGBuoys*$isSubmergedMult;
        if (V_Calc_pDots and $verbose>=3){pq($CGForcesBuoyancy)}
        
        $CGNetAppliedForces(2*$nCGs:-1) += $CGForcesBuoyancy;
    }
 
    my $CGForcesGravity = -$gravity*$CGWts;
    if (V_Calc_pDots and $verbose>=3){pq($CGForcesGravity)}
    # Need to recompute if stripping.
    
    $CGNetAppliedForces(2*$nCGs:-1) += $CGForcesGravity;
    if ($verbose>=3){
        my $CGNetXs = $CGNetAppliedForces(0:$nCGs-1);
        my $CGNetYs = $CGNetAppliedForces($nCGs:2*$nCGs-1);
        my $CGNetZs = $CGNetAppliedForces(2*$nCGs:-1);
        pq($CGNetXs,$CGNetYs,$CGNetZs);
    }
    
    $pDots  += ($CGNetAppliedForces x $dCGQs_dqs)->flat;
    if (V_Calc_pDots and $verbose>=3){pq($pDots)}
    
    if ($numLineSegs and !$programmerParamsPtr->{freeLineNodes}){
        
        Calc_pDotsLineMaterial();
        if (V_Calc_pDots and $verbose>=3){pq($pDotsLineK,$pDotsLineC)}
        
        $pDots($idx0:-1) += $pDotsLineK+$pDotsLineC;
        if (V_Calc_pDots and $verbose>=3){print " After Line: pDots=$pDots\n"}
    }
    
    

    if (0 and $numRodSegs){
        # Rod stuff, not implemented yet in 3D.  And may not be implemented this way, anyhow.
 
=begin comment
        #    if (!$programmerParams{zeroPDotsKE} and $nRodNodes>0){
        if ($numRodSegs and !$programmerParamsPtr->{zeroPDotsKE}){
            Calc_pDotsKE();
            if (DEBUG and V_Calc_pDots and $verbose>=4){pq $pDotsKE}
            
            # Be careful to put the result in the right place.  See comments in Calc_pDotsKE().
            $pDots(0:$idx0-1) += $pDotsKE;
            if (DEBUG and V_Calc_pDots and $verbose>=5){print " After KE: pDots=$pDots\n";}
        }
=end comment
=cut
        # Compute the acceleration due to the potential energy.  First, from the rod thetas:
        
        # First, deal with the rod nodes bending energy and internal friction:
        my ($pThetaDotsK,$pThetaDotsC);
        if (0 and $numRodSegs){
            
            
            die "Not yet implemented in 3D\n";
            ### This needs to be replaced by code that computes the 3D bending at the rod nodes (incl handle top, but not rod tip.
            
            Calc_pDotsRodMaterial();

=begin comment
             #        if (!$programmerParams{zeroPThetaDots}){

            ## This handles the angle alignment constraint force from the driver motion, but not the cartesian force on the handle base.  That force is applied in Calc_pDotsConstraints.
 
            my $pThetaDotsK    = -$rodKsNoTip*$dthetas;
            my $pThetaDotsC    = -$rodCsNoTip*$dthetaDots;
  
             if (DEBUG and V_Calc_pDots and $verbose>=5){pq($pThetaDotsK,$pThetaDotsC)}
            # NOTE:  The tip node DOES NOT contribute to the bending energy since the line connects to the rod there, and there is no elasticity at that hinge point.  However, the handle node DOES contribute.  Positive theta should yield a negative contribution (??) to thetaDot.  Aside from the constants, we are taking the theta derivative of (theta/segLen)^2, so 2*theta/(segLen^2), and I have absorbed all the constants into multiplier. ??  ???

            $pDots(0:$nThetas-1) += $pThetaDotsK+$pThetaDotsC;

            if (DEBUG and V_Calc_pDots and $verbose>=5){print " After thetas: pDots=$pDots\n";}
=end comment
=cut
        }
    
        
        my $tFract = SmoothChar(pdl($t),$tipReleaseStartTime,$tipReleaseEndTime);
            # Returns 1 if < start time, and 0 if > end time.
        if ($holding == 1 and $tFract == 1){    # HOLDING
            
            die "Not yet implemented in 3D.\n";
            
            $pDots($idy0-1) .= 0;   # Overwrite any tip adjustments that other Calcs might have provided.
            $pDots(-1)      .= 0;
            
            my $pDotsTip_HOLD = Calc_pDotsTip_HOLD($t,$tFract);
            $pDots += $pDotsTip_HOLD;
            if (DEBUG and V_Calc_pDots and $verbose>=4){pq $pDotsTip_HOLD}
            if (DEBUG and V_Calc_pDots and $verbose>=5){print " After tip hold: pDots=$pDots\n";}
            
        } elsif ($holding == -1 and $tFract>0 and $tFract<1){   # RELEASING

            die "Not yet implemented in 3D.\n";

            my $pDotsTip_SOFT_RELEASE = Calc_pDotsTip_SOFT_RELEASE($t,$tFract);
            $pDots += $pDotsTip_SOFT_RELEASE;
            if (DEBUG and V_Calc_pDots and $verbose>=4){pq $pDotsTip_SOFT_RELEASE}
            if (DEBUG and V_Calc_pDots and $verbose>=5){print " After tip soft release: pDots=$pDots\n";}
        }
    }
   
    
	if (DEBUG and V_Calc_pDots and $verbose>=4){ pq $pDots}
    # return $pDots;
}



sub Set_HeldTip { use constant V_Set_HeldTip => 0;
    my ($t) = @_;   # $t is a PERL scalar.
    
    # During hold, the ($dxs(-1),$dys(-1)) are not treated as dynamical variables.  Instead, they are made into quantities dependent on all the remaining dynamical varibles and the fixed fly position ($XTip0,$YTip0).  This takes the fly's mass and drag out of the calculation, but the mass of the last line segment before the fly still acts at that segment's cg and its drag relative to its spatial orientation, due to changes in the cg location caused by the motion of the last remaining node ($Xs(-2),$Ys(-2)).
    
    if (!$numLineSegs){die "Hold not allowed if there are no line nodes."}
 
    Calc_Driver($t);
    Calc_dQs();
    
    $XTip0 = $driverX+sumover($dXs);
    $YTip0 = $driverY+sumover($dYs);
    $ZTip0 = $driverY+sumover($dZs);
    if (DEBUG and V_Set_HeldTip and $verbose>=4){print "\nSet_HOLD:\n";pq($XTip0,$YTip0,$ZTip0,$qs,$ps);print "\n";}
}


sub Get_HeldTip {
    return ($XTip0,$YTip0,$ZTip0);
}


sub Set_ps_From_qDots {
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
    if ($numRodSegs){Calc_CartesianPartials()};    # Else done once during initialization.
    Calc_ExtCGVs();
    Calc_CGQDots();

    my $Ps = $CGQMasses*$CGQDots;
    
    #??? is this true???  I don't think so. $ps are the conjugate momenta computed by d/dqDots of the KE.
    #But maybe it comes to the same thing.'
    $ps .= ($Ps x $dCGQs_dqs)->flat;

    if ($verbose>=3){pq $ps}
    #    return $ps;
}


sub DE_GetStatus {
    return $DE_status;
}

sub DE_GetErrMsg {
    return $DE_errMsg;
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
my ($maxTipDiff);
my ($maxLineStrains,$maxLineVs);
my ($plotLineVXs,$plotLineVYs,$plotLineVZs,$plotLineVAs,$plotLineVNs,$plotLine_rDots);

sub DE_InitExtraOutputs {
    
    $maxTipDiff         = zeros(1)->flat;
    
    $maxLineStrains = zeros($numLineNodes);
    $maxLineVs      = zeros($numLineNodes);
    
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



my $prevT=0;

sub DE { use constant V_DE => 1;
    my $verbose = $verbose;    # Sic, isolate the global from possible change here.
    my ($t,$caller)= @_;  # The args are PERL scalars.  The only callers are DEfunc_GSL() and DEjacHelper_GSL(), both of which load our package global $dynams.
    
    ## Do a single DE step.
    ## Express the differential equation of the form required by RungeKutta.  The y vector flat (or a row vector).
    my $nargin = @_;
    
    if ($caller eq "DEjac_GSL" and V_DE and $verbose<4){$verbose = 0}
    
    $DE_numCalls++;
    if (V_DE and $verbose>=3){print "\nEntering DE (t=$t,caller=$caller),call=$DE_numCalls ...\n"}
    #pq($t);
    $tDynam = $t;
    
    if (DEBUG and V_DE and $verbose>=4){
        my $dt = $t-$prevT;
        if ($dt){pq($dt)}
        $prevT = $t;
    }
    
    if (V_DE and $verbose>=3){
        #pq($dynams);
        #pqInfo($dynams);
        pq($dxs,$dys,$dzs);
    }
    
    if (DEBUG and V_DE and $verbose>=5){pq($qs,$ps)};

    my $dynamDots   = zeros($dynams);

   # Run control from caller:
    &{$runControlPtr->{callerUpdate}}();
    if ($runControlPtr->{callerRunState} != 1) {
    
        $DE_errMsg = "User interrupt";
        $DE_status = 1;
        return ($dynamDots);
    }
    
    if ($stripping){    # Must be done before Calc_dQs().
        AdjustFirstSeg_STRIPPING($t);
    }
    
    Calc_dQs();
    if (V_DE and $verbose>=4){pq($lineStrains)}
        # Could compute $Qs now, but don't need them for what we do here.
    
    if ($numRodSegs){Calc_CartesianPartials()};    # Else done once during initialization by Calc_CartesianPartials_NoRodSegs().
        # Updates $dCGQs_dqs, $d2CGQs_d2thetas (if $numRodNodes) and $dCGQs_dqs.
    ## in the new scheme, this would never be done here.
    
    # Set global coords and external velocities.  See Set_ps_From_qDots():
    Calc_Driver($t);
    # This constraint drives the whole cast. Updates the driver globals.
    
    Calc_ExtCGVs();
    if (DEBUG and V_DE and $verbose>=5){pq($extCGVs);print "D\n";}
       # The contribution to QDots from the driving motion only.  This needs only $dQs_dqs.  It is critical that we DO NOT need the internal contributions to QDots here.
    
    Calc_qDots();
    if (DEBUG and V_DE and $verbose>=5){pq($qDots);print "E\n";}
        # At this point we can find the NEW qDots.  From them we can calculate the new INTERNAL contributions to the cartesian velocities, $intVs.  These, always in combination with $extCGVs, making $Qdots are then used for then finding the contributions to the NEW pDots due to both KE and friction, done in Calc_pDots() called below.
    
    Calc_CGQDots();
    if (DEBUG and V_DE and $verbose>=5){pq($CGQDots);print "F\n";}
    # Finds the new internal cartesian velocities and adds them to $extCGVs computed above.

    Calc_pDots($t);
    if (DEBUG and V_DE and $verbose>=5){pq($pDots);print "G\n";}
    
    $dynamDots(0:$nqs-1)        .= $qDots;
    $dynamDots($nqs:2*$nqs-1)   .= $pDots;
    
    # To indicate progress, tell the user when the solver first passes the next reporting step.  Cf "." in DEfunc_GSL() and "_" in DEjacHelper_GSL():
    if ($verbose>=2 and $t >= $T0+$DE_reportStep*$dT){
        printf("\nt=%.3f   ",$tDynam);
        $DE_reportStep++;
    }
    
    if (DEBUG and V_DE and $verbose>=5){pq($dynamDots);print"\n"}
    if (V_DE and $verbose>=3){print "... Exiting DE\n"}
    
    return ($dynamDots);   # Keep in mind that this return is a global, and you may want to make a copy when you make use of it.
}                                                                            


my @aDynams0Block;   # Returned by initialization call to DEfunc_GSL


sub DEset_Dynams0Block {
    my (@a) = @_;

    PrintSeparator ("Initialize block dynams",3);

    @aDynams0Block = @a;
    if ($verbose>=3){pq(\@aDynams0Block)}

}



sub DEfunc_GSL { use constant V_DEfunc_GSL => 1;
    my ($t,@aDynams) = @_;
    
    ## Wrapper for DE to adapt it for calls by the GSL ODE solvers.  These do not pass along any params beside the time and dependent variable values, and they are given as a perl scalar and perl array.  Also, the first call is made with no params, and requires the initial dependent variable values as the return.
    
    unless (@_) {if ($verbose>=3){print "Initializing DEfunc_GSL\n"; pq(\@aDynams0Block)}; return @aDynams0Block}
    #unless (@_) {return @aDynams0Block}

    if ($verbose>=2 and $DEfunc_dotCount % $DEdotsDivisor == 0){print "."}
    $DEfunc_dotCount++;     # starts new after each dash.
    $DEfunc_numCalls++;
    
    $dynams .= pdl(@aDynams);   # Loading my global here.  DE() will use it as is.
        # This pdl call isolates @aDynams from $dynams, so nothing I do will mess up the solver's data.  $dynams is a flat pdl.
    if (DEBUG and V_DEfunc_GSL and $verbose>=4){pq($t,$dynams)}
    
    my ($dynamDots) = DE($t,"DEfunc_GSL");
    if (DEBUG and V_DEfunc_GSL and $verbose>=4){pq($DE_status,$dynamDots)}
    
    my @aDynamDots = $dynamDots->list;

    # AS DOCUMENTED in PerlGSL::DiffEq: If any returned ELEMENT is non-numeric (eg, is a string), the solver will stop solving and return all previously computed values.  NOTE that they seem really to mean what they say.  If you set the whole return value to a string, you (frequently) get a segmentation fault, from which the widget can't recover.
    if ($DE_status){$aDynamDots[0] = "stop$vs"}
    
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
    
    PrintSeparator("Initialize JAC",3);
    
    $JACfac             = zeros(0);
    #my $ynum0           = DEjacHelper_GSL();
    my $ynum0           = 1 + 2*$nqs;
    $JACythresh         = 1e-8 * ones($ynum0);
    $JACytyp            = zeros($JACythresh);
    if (V_JACInit and $verbose>=3){pq($JACythresh,$JACytyp,$ynum0)}
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
    if (V_DEjac_GSL and $verbose>=3){pq($JACfac)}
    
    my $dFdt    = $dfdy(0,:)->flat->unpdl;
    my $dFdy    = $dfdy(1:-1,:)->unpdl;
    if (DEBUG and V_DEjac_GSL and $verbose>=4){pq($JACfac,$nfcalls,$dFdy,$dFdt)}

    return ($dFdy,$dFdt);
}

# Required package return value:
1;




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


# MODIFICATION HISTORY =================================================================

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

#  19/02/01 - Began 3D version of the hamilton code. At first, will implement only sink version to avoid the complication of dealing with second derivatives in Calc_CartesianPartials.  I will use the convention of a right-hand X,Y,Z coordinate system, with X pointing downstream and Z pointing upward.

#  19/02/02 - How to choose the rod dynamical variables is a delicate question.  Simply choosing angles relative to say the (X-Y) and (X-Z) planes leaves the possibility of indeterminacy (as, for example, when a rod segment is vertical.  That there is a usable set of dynmaical variables is shown by imagining that each rod node is actually a double (1-D) hinge arrangement, with a first hinge allowing motion in a fixed plane containing the previous segment, and a short segment later, a hinge in the perpendicular direction (as defined when the first hinge is not deflected).  It is clear that the specification of these hinge angles uniquely determines (and is determined by) the rod configuration.

#  For the moment, I will just insert placeholders for the rod dynamical variables.

#  19/02/20 - The name sink was replaced by swing, which better reflects 3D nature of the motion and all the new capabilities (3D rod tip motion, water velocity profiles in both stream depth and cross-stream, sink delay and stripping).  I realized, in the context of swing, that the matrix inversion that was so costly and used at every step in Calc_qDots() need only be computed once (during initialzation).  This made the program run much faster.  At the same time, I ruthlessly removed all unnecessary copying.

#  The code was made more streamlined, especially Calc_pDots(), which now collects all applied CG forces before making a matrix multiplication with dCGQs_dqs.  The verbose system was also cleaned up to make $verbose = 2 the standard user mode, with good progress reporting to the status window, but very little print overhead.  Verbose = 3 is also expected to be helpful to the user, showing the dynamical variables and the CG forces at each integration step, and in the better context of a terminal window, but at the cost of much increased execution time.  $verbose >= 4 is always meant for debugging, and the code is only included if the constant DEBUG flag is set in RCommon.

#  I believe I understand that I can use the dqs = (dxs,dys,dzs) line cartesian dynamical variables, with their huge saving of not recomputing the inverse (essentially because the KE is not dqs dependent, only dqDots dependent), for the rod as well. This adds the extra expense of one more dynamical variable for each inertial rod node, and the inclusion of the rod segment stretching PE in place of just a fixed segment length constraint, but this will be easily paid for by not having to recompute inv.  I hope to implement this soon.

#  19/02/20 - Switched to rod handling described in the previous paragraph.  To get swinging working, but leave casting unimplemented at first.

