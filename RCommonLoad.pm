#!/usr/bin/perl -w

# RCommonInterface.pm

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

package RCommonLoad;

## All the common handling code for the control panels.

use warnings;
use strict;

our $VERSION='0.01';

use Exporter 'import';
our @EXPORT = qw(LoadLine LoadLeader LoadTippet $loadedLenFt $loadedGrsPerFt $loadedDiamsIn $loadedElasticDiamsIn $loadedElasticModsPSI $loadedDampingDiamsIn $loadedDampingModsPSI $lineIdentifier $flyLineNomWtGrPerFt $leaderIdentifier $leaderStr $leaderLenFt $leaderElasticModPSI $leaderDampingModPSI $tippetStr $tippetLenFt $tippetElasticModPSI $tippetDampingModPSI $loadedVolsPerFt @lineFieldsDisable @leaderFieldsDisable);

use RCommon;

use Carp;

use utf8;   # To help pp, which couldn't find it in require in AUTOLOAD.  This worked!

use PDL;
    # Import main PDL module (see PDL.pm for equivalents).  In particular, imports PDL::Math, which redefines many POSIX math functions.  To get the original, call POSIX::aFunction.

use PDL::NiceSlice;
use PDL::AutoLoader;    # MATLAB-like autoloader.
use PDL::Options;     # Good to keep in mind. See RLM.
PDL::no_clone_skip_warning;

use Switch;
use Scalar::Util qw(looks_like_number);

use File::Basename;
use File::Spec::Functions qw ( rel2abs abs2rel splitpath );

use RUtils::Print;


# Total line (flyline, leader, tippet) variables:
our ($loadedLenFt,$loadedGrsPerFt,$loadedDiamsIn,$loadedElasticDiamsIn,$loadedElasticModsPSI,$loadedDampingDiamsIn,$loadedDampingModsPSI);
our $loadedVolsPerFt;


# File loading ============================

our ($lineIdentifier,$flyLineNomWtGrPerFt);

my $lineFieldsDisableInds;
our @lineFieldsDisable;

sub SwapLineFields {
    my ($fromStorage) = @_;

	if ($fromStorage){

		$rps->{line}{nomWtGrsPerFt}			= $rps->{lineLevel}{nomWtGrsPerFt};
		$rps->{line}{estimatedSpGrav}		= $rps->{lineLevel}{estimatedSpGrav};
		$rps->{line}{nomDiamIn}				= $rps->{lineLevel}{nomDiamIn};
		$rps->{line}{coreDiamIn}			= $rps->{lineLevel}{coreDiamIn};
		$rps->{line}{coreElasticModulusPSI}
								= $rps->{lineLevel}{coreElasticModulusPSI};
		$rps->{line}{dampingModulusPSI}
								= $rps->{lineLevel}{dampingModulusPSI};

		print "Swapping from storage...\n panel fields: $rps->{line}{nomWtGrsPerFt},$rps->{line}{estimatedSpGrav},$rps->{line}{nomDiamIn},$rps->{line}{coreDiamIn},$rps->{line}{coreElasticModulusPSI},$rps->{line}{dampingModulusPSI}.\n\n";
		
		
	} else {  # to storage
	
		# Just swap the enabled values.
		my $enabled = ones(6);
		$enabled($lineFieldsDisableInds) .= 0;
		
		if($enabled(0)){$rps->{lineLevel}{nomWtGrsPerFt}	= $rps->{line}{nomWtGrsPerFt} }
		if($enabled(1)){$rps->{lineLevel}{estimatedSpGrav}	= $rps->{line}{estimatedSpGrav} }
		if($enabled(2)){$rps->{lineLevel}{nomDiamIn}		= $rps->{line}{nomDiamIn} }
		if($enabled(3)){$rps->{lineLevel}{coreDiamIn}		= $rps->{line}{coreDiamIn} }
		if($enabled(4)){$rps->{lineLevel}{coreElasticModulusPSI}
										= $rps->{line}{coreElasticModulusPSI} }
		if($enabled(5)){$rps->{lineLevel}{dampingModulusPSI}
										= $rps->{line}{dampingModulusPSI} }
		
		print "Swapping to storage...\n \$enabled = $enabled\n storage fields: $rps->{lineLevel}{nomWtGrsPerFt},$rps->{lineLevel}{estimatedSpGrav},$rps->{lineLevel}{nomDiamIn},$rps->{lineLevel}{coreDiamIn},$rps->{lineLevel}{coreElasticModulusPSI},$rps->{lineLevel}{dampingModulusPSI}.\n\n";
	}
}


sub LoadLine {
    my ($lineFile,$updatingPanel,$initialize) = @_;
		# If we are not updating the panel, we are beginning a run.

    ## Process leaderFile if passed, otherwise set leader as indicated by the parameters.  If trying to read a file and is not able to open it, noop, and no side effects, returning 0.  In all other cases, if updating, just plows ahead, always returning 1.  If not updating, returns 0 on detecting error.
	
	my $stdPrint = (!$updatingPanel and $verbose>=2) ? 1 : 0;

    #if ($stdPrint){PrintSeparator("Loading line")}
    if (1){PrintSeparator("Loading line")}
	
    my $ok = 1;
	
	my ($lineLenFt,$lineGrsPerFt,$lineDiamsIn,
		$lineElasticDiamsIn,$lineElasticModsPSI,
		$lineDampingDiamsIn,$lineDampingModsPSI);

    if ($lineFile) {
        
        #if ($stdPrint){print "Data from $lineFile.\n"}
        if (1){print "Data from $lineFile.\n"}
		
		my $inData;
        open INFILE, "< $lineFile" or $ok = 0;
        if (!$ok){print "ERROR: In attempting to load line, could not read file $lineFile. $!\n\n";return 0}
		{
			local $/;
        	$inData = <INFILE>;
		}
        close INFILE;

		# Always swap the currently enabled fields to level storage.  This keeps the storage up to date:
		if ($updatingPanel){
			# Do this early.

			if (!$initialize){	# Disable everything.
				SwapLineFields(0); # Swap out only enabled fields.
				SwapLineFields(1);
			} # else, just use the fields that were loaded.
		}

        if ($inData =~ m/^Identifier:\t(\S*).*\n/mo)
        {$lineIdentifier = $1; }
        if ($stdPrint){print "lineID = $lineIdentifier\n"}
        
        $rps->{line}{identifier} = $lineIdentifier;
		
		my ($coreDiam,$specGravity,$elasticMod,$dampingMod);
		
        # Find the line with "NominalWt" having the desired value:
    	$flyLineNomWtGrPerFt    = $rps->{line}{nomWtGrsPerFt};
		
        my ($str,$rem);
        my $ii=0;
		my $foundIt = 0;
		my $okWeight = 0;
        while ($inData =~ m/^NominalWt:\t(-?\d*)\n/mo) {
            my $tWeight = $1;
			
			# I'm looking for ANY weight group, and will record all its info.  But I will keep looking until I find the particular wt I was seeking.  If nothing is found, $tWeight will be zero, an early indication to the user that the file is inadequate:
			
			$rem = $';
			
			if (!$foundIt){	# Stop collecting data if found, but keep counting.
			
				$okWeight = $tWeight;

				$lineGrsPerFt = GetMatFromDataString($rem,"Weights");
				if ($lineGrsPerFt->isempty){last}
				
				$lineDiamsIn = GetMatFromDataString($rem,"Diameters");
				if ($lineDiamsIn->isempty){   # Compute from estimated density:
					my $spGrav = $rps->{line}{estimatedSpGrav};
					my $massesPerCm = $lineGrsPerFt*$grainsToGms/$feetToCms; # gramWts/cm.
					my $displacements   = $massesPerCm/$waterDensity;  # cm**2;
					my $areas			= $displacements/$spGrav;
					$lineDiamsIn      = sqrt($areas)/$inchesToCms;
					#pq($spGrav,$massesPerCm,$displacements,$areas);
				}
				
				# Look for any other parameter specifications below that location in the file (this should be improved):
				$specGravity	= GetValueFromDataString($rem,"SpecificGravity");
				$coreDiam		= GetValueFromDataString($rem,"CoreDiameter");
				$elasticMod		= GetValueFromDataString($rem,"ElasticModulus");
				$dampingMod		= GetValueFromDataString($rem,"DampingModulus");
				pq($okWeight,$specGravity,$coreDiam,$elasticMod,$dampingMod);
				
				# Exit loop if desired wt was found:
				if ($okWeight == $flyLineNomWtGrPerFt){
					$foundIt = 1;
					#last;	# Keep counting.
				}
			}
		
            $inData = $';
            $ii++;
            if ($ii>15){last;}
        }
        if (!$foundIt){print "ERROR: Failed to find line weight $flyLineNomWtGrPerFt in file $lineFile.\n\n"; if(!$updatingPanel){return 0} }
		
		my $numWts = $ii;
		pq($numWts);
		# If there is only one nominal wt found, set that parameter and disable its field.
		
		# Write params to control panel:
		if ($updatingPanel){

			my $disable = zeros(6);
			
			$disable(0) .= ($numWts <= 1) ? 1 : 0;
			$disable(1) .= (defined($specGravity)) ? 1 : 0;
			$disable(2) .= 1; # Nom diam always if there is a file.
			$disable(3) .= (defined($coreDiam)) ? 1 : 0;
			$disable(4) .= (defined($elasticMod)) ? 1 : 0;
			$disable(5) .= (defined($dampingMod)) ? 1 : 0;
			
			# Then, immediately swap all the level fields back from storage.  This should allow, at least on a subsequent call, the desired nominal grains per foot in a selected file:
			SwapLineFields(1);
			
			# Overwrite the fields set from the file.  These will be disabled.
			if ($disable(0)){$rps->{line}{nomWtGrsPerFt}			= $okWeight}
			if ($disable(1)){$rps->{line}{estimatedSpGrav}			= $specGravity}
			if ($disable(2)){$rps->{line}{nomDiamIn}				= "---"}
			if ($disable(3)){$rps->{line}{coreDiamIn}				= $coreDiam}
			if ($disable(4)){$rps->{line}{coreElasticModulusPSI}	= $elasticMod}
			if ($disable(5)){$rps->{line}{dampingModulusPSI} 		= $dampingMod}

			# Flag fields for disabling by the caller:
			$lineFieldsDisableInds = which($disable);
			pq($disable);
			print("\$lineFieldsDisableInds = $lineFieldsDisableInds\n");
			
			@lineFieldsDisable = ();
			for (my $ii=0;$ii<$disable->nelem;$ii++){
				if ($disable($ii)){push(@lineFieldsDisable,$main::lineFields[$ii])}
			}
			print "LoadLine: \@lineFieldsDisable = @lineFieldsDisable\n";
			return 1;
		}
		
    }else{  # Use params to define a level line.
	
		if ($updatingPanel){	# This call can't fail.
		
			print "Line set from params\n";
			
			if (!$initialize){	# Disable everything.
				SwapLineFields(0); # Swap out only enabled fields.
				SwapLineFields(1);
			} # else, just use the fields that were loaded.
			
			$lineFieldsDisableInds	= zeros(0);
			@lineFieldsDisable		= ();
			return 1;
		}
		
		# Except for nomWtGrsPerFt, always start with the stored level values and enable all fields:
		#SwapLineFields(1); # From storage.
		$lineFieldsDisableInds = zeros(0);
		
        # Create a uniform line array.  This can have any weight:
        $lineIdentifier = "Level";
        $rps->{line}{identifier}	= $lineIdentifier;
        $flyLineNomWtGrPerFt		= $rps->{line}{nomWtGrsPerFt};
		
        $lineGrsPerFt         = $rps->{line}{nomWtGrsPerFt}*ones(60);    # Segment wts (ie, at cg)
        $lineDiamsIn          = $rps->{line}{nomDiamIn}*ones(60);    # Segment diams
        
        if ($stdPrint){print "Level line constructed from parameters.\n"}
    }
	
	# Code common to setting from both file and params:
    $lineElasticDiamsIn	= $rps->{line}{coreDiamIn}*ones($lineDiamsIn);
    $lineElasticModsPSI	= $rps->{line}{coreElasticModulusPSI}*ones($lineDiamsIn);
    
    $lineDampingDiamsIn	= $lineDiamsIn;   # Sic, at least for now.
    $lineDampingModsPSI	= $rps->{line}{dampingModulusPSI}*ones($lineDiamsIn);
    
    if ($verbose>=3){pq($lineGrsPerFt,$lineDiamsIn)}
    if ($verbose>=3){pq($lineElasticDiamsIn,$lineElasticModsPSI,$lineDampingDiamsIn,$lineDampingModsPSI)}
	
	$loadedLenFt = $lineLenFt;
    
    $loadedGrsPerFt         = $lineGrsPerFt;
    $loadedDiamsIn          = $lineDiamsIn;
    $loadedElasticDiamsIn   = $lineElasticDiamsIn;
    $loadedElasticModsPSI   = $lineElasticModsPSI;
    $loadedDampingDiamsIn   = $lineDampingDiamsIn;
    $loadedDampingModsPSI   = $lineDampingModsPSI;
	
    return $ok;
}


# Leader variables:
our ($leaderIdentifier,$leaderStr);
our ($leaderLenFt,$leaderElasticModPSI,$leaderDampingModPSI);

my $leaderFieldsDisableInds;
our @leaderFieldsDisable;

sub SwapLeaderFields {
    my ($fromStorage) = @_;
	
	## I don't do any copying of the menu field here.  That is left to LoadLeader().

	if (!$fromStorage){

		print "Swapping to storage:\n";
		# Just swap the enabled values.
		my $enabled = ones(7);
		$enabled($leaderFieldsDisableInds) .= 0;

		if($enabled(0)){$rps->{leaderLevel}{text}			= $rps->{leader}{text}}
		if($enabled(1)){$rps->{leaderLevel}{lenFt}			= $rps->{leader}{lenFt}}
		if($enabled(2)){$rps->{leaderLevel}{wtGrsPerFt}		= $rps->{leader}{wtGrsPerFt}}
		if($enabled(3)){$rps->{leaderLevel}{diamIn}			= $rps->{leader}{diamIn}}
		if($enabled(4)){$rps->{leaderLevel}{coreDiamIn}		= $rps->{leader}{coreDiamIn}}
		if($enabled(5)){$rps->{leaderLevel}{coreElasticModulusPSI}
													= $rps->{leader}{coreElasticModulusPSI}}
		if($enabled(6)){$rps->{leaderLevel}{dampingModulusPSI}
													= $rps->{leader}{dampingModulusPSI}}
		print "Swapping to storage...\n \$enabled = $enabled\n storage fields: $rps->{leaderLevel}{text},$rps->{leaderLevel}{lenFt},$rps->{leaderLevel}{wtGrsPerFt},$rps->{leaderLevel}{diamIn},$rps->{leaderLevel}{coreDiamIn},$rps->{leaderLevel}{coreElasticModulusPSI},$rps->{leaderLevel}{dampingModulusPSI}.\n\n";
		
	} else {  # from storage
		
		$rps->{leader}{text}					= $rps->{leaderLevel}{text};
		$rps->{leader}{lenFt}					= $rps->{leaderLevel}{lenFt};
		$rps->{leader}{wtGrsPerFt}				= $rps->{leaderLevel}{wtGrsPerFt};
		$rps->{leader}{diamIn}					= $rps->{leaderLevel}{diamIn};
		$rps->{leader}{coreDiamIn}				= $rps->{leaderLevel}{coreDiamIn};
		$rps->{leader}{coreElasticModulusPSI}
								= $rps->{leaderLevel}{coreElasticModulusPSI};
		$rps->{leader}{dampingModulusPSI}
								= $rps->{leaderLevel}{dampingModulusPSI};

		print "Swapping from storage...\n panel fields: $rps->{leader}{text},$rps->{leader}{lenFt},$rps->{leader}{wtGrsPerFt},$rps->{leader}{diamIn},$rps->{leader}{coreDiamIn},$rps->{leader}{coreElasticModulusPSI},$rps->{leader}{dampingModulusPSI}.\n";
	}
}

sub LoadLeader {
    my ($leaderFile,$updatingPanel,$initialize) = @_;
		# If we are not updating the panel, we are beginning a run.
	
    ## Process leaderFile if defined, otherwise set leader as indicated by the menu choice.
	
	my $stdPrint = (!$updatingPanel and $verbose>=2) ? 1 : 0;

    #if ($stdPrint){PrintSeparator("Loading leader")}
    if (1){PrintSeparator("Loading leader")}
	
    my $ok = 1;

    my ($leaderGrsPerFt,$leaderDiamsIn,$leaderElasticDiamsIn,$leaderElasticModsPSI,$leaderDampingDiamsIn,$leaderDampingModsPSI);

	my ($weights,$diams,$length,$nomWt,$nomDiam,$coreDiam,$elasticMod,$dampingMod,$specGravity,$material);

    if ($leaderFile) {
        
        if ($stdPrint){print "Data from $leaderFile.\n"}
		
        my $inData;
        open INFILE, "< $leaderFile" or $ok = 0;
        if (!$ok){print "ERROR: In attempting to load leader, could not read file $leaderFile. $!\n";return 0}
		{
			local $/;
        	$inData = <INFILE>;
		}
        close INFILE;
        
		if ($updatingPanel){
			# Swap enabled fields to storage.  If we're coming from params, the menu field will be enabled.

			if (!$initialize){
				SwapLeaderFields(0); # Swap out only enabled fields.
				SwapLeaderFields(1);
			} # else, just use the fields that were loaded.
		}

        if ($inData =~ m/^Identifier:\t(\S*).*\n/mo)
        {$leaderIdentifier = $1; }
        #if ($stdPrint){print "leaderID = $leaderIdentifier\n"}
        if (1){print "leaderID = $leaderIdentifier\n"}

        $leaderStr = $leaderIdentifier;
		
        $rps->{leader}{identifier} = $leaderIdentifier;
 
		# See what's available in the file:
		$weights 		= GetMatFromDataString($inData,"Weights");
		$diams			= GetMatFromDataString($inData,"Diameters");
		$length			= GetValueFromDataString($inData,"Length");
		#$nomWt			= GetValueFromDataString($inData,"NominalWeight");
		$coreDiam		= GetValueFromDataString($inData,"CoreDiameter");
		$elasticMod		= GetValueFromDataString($inData,"ElasticModulus");
		$dampingMod		= GetValueFromDataString($inData,"DampingModulus");

		$specGravity	= GetValueFromDataString($inData,"SpecificGravity");
		$material		= GetWordFromDataString($inData,"Material");
		#pq($weights,$diams,$specGravity,$material,$elasticMod,$dampingMod);
		
		if ($weights->isempty and $diams->isempty){$ok=0; print "ERROR: Leader file must have values for Weights or Diameters, or both.\n";}
		
		if (defined($material)){
		   switch ($material) {
				case "mono"     {}
				case "fluoro"   {}
				else {
					if ($stdPrint){print "WARNING:  Found material  \"$material\".  The only recognized leader materials are \"mono\" and \"fluoro\". Defaulting to \"mono\".\n"}
					$material = "mono";
				}
			}
		} else { $material = "mono"}	# Assume mono.

		if (!defined($specGravity)){
		   switch ($material) {
				case "mono"     {   $specGravity	= 1.01}
				case "fluoro"   {   $specGravity	= 1.85}
			}
		}

		if (!$weights->isempty and !$diams->isempty){
			if ($weights->nelem != $diams->nelem){$ok=0; print "Error:  If leader file has both Weights and Diameters, they must have the same number of elements.\n"}
			$specGravity = undef;	# We can't have it both ways!
			if ($verbose>=3){	# Test uniformity of specific gravity
				my $vols	= ($pi/4)*$diams**2;	 # in**3
				my $testSpecGravities =
					$weights/(12*$waterDensityGrsPerIn3*$vols);
				if ($stdPrint){print "Leader computed specGravities = $testSpecGravities\n"}
			}
		} elsif (!$diams->isempty) {	# Figure weights
			my $vols	= ($pi/4)*$diams**2;	 # in**3
			$weights	= 12*$waterDensityGrsPerIn3*$specGravity*$vols;	# grs/ft
		} else {						# Figure diams
			my $vols	= $weights/(12*$waterDensityGrsPerIn3*$specGravity); # in**3
			$diams	= sqrt((4/$pi)*$vols);		# inches
		}

		if (!$ok and !$updatingPanel){return 0}


		# Write params to control panel:
		if ($updatingPanel){

			# Swap all the level fields back from storage.  This gives us a set of numerical starting values.  Based on what was found in the file, some of these will be overwritten:
			SwapLineFields(1);

			my $disable = zeros(7);
			
			# Set fields for disabling if they are given values in the file or if it makes no sense to let the user set them:
			$disable(0) .= 1;	# Always disable the menu.
			$disable(1) .= (defined($length))		? 1 : 0;
			$disable(2) .= 1; # Disable nom wt always if there is a file.
			$disable(3) .= 1; # Disable nom diam always if there is a file.
			$disable(4) .= 1; # Disable core diam always if there is a file.  However, it is allowed for the file itself to set the core diameter.
			$disable(5) .= (defined($elasticMod))	? 1 : 0;
			$disable(6) .= (defined($dampingMod))	? 1 : 0;
			
			if (!defined($coreDiam)){$coreDiam = "---"}
			
			# Overwrite the fields set from the file.  These will be disabled.
			if ($disable(0)){$rps->{leader}{text}					= "---"}
			if ($disable(1)){$rps->{leader}{lenFt}					= $length}
			if ($disable(2)){$rps->{leader}{wtGrsPerFt}				= "---"}
			if ($disable(3)){$rps->{leader}{diamIn}					= "---"}
			if ($disable(4)){$rps->{leader}{coreDiamIn}				= $coreDiam}
			if ($disable(5)){$rps->{leader}{coreElasticModulusPSI}	= $elasticMod}
			if ($disable(6)){$rps->{leader}{dampingModulusPSI} 		= $dampingMod}

			# Flag fields for disabling by the caller:
			$leaderFieldsDisableInds = which($disable);
			pq($disable);
			print("\$leaderFieldsDisableInds = $leaderFieldsDisableInds\n");
			
			@leaderFieldsDisable = ();
			for (my $ii=0;$ii<$disable->nelem;$ii++){
				if ($disable($ii)){push(@leaderFieldsDisable,$main::leaderFields[$ii])}
			}
			print "LoadLeader: \@leaderFieldsDisable = @leaderFieldsDisable\n";
			return 1;
		}

		# We are running.  Record the results of our machinations:
		$leaderGrsPerFt		= $weights;
		$leaderLenFt		= $leaderGrsPerFt->nelem;
		if (defined($length)){
			if ($leaderLenFt < $length){$ok=0; print "ERROR: If Length is given in the file, the number of diameter and weight entries must be no less than that length.\n"; return $ok;}
			else {$leaderLenFt = $length}
		}
		
		$leaderDiamsIn			= $diams;
		$leaderElasticDiamsIn	=
			(defined($coreDiam)) ? $coreDiam*ones($diams) : $leaderDiamsIn;
		$leaderDampingDiamsIn	= $leaderDiamsIn;
			# Assume the coating plays a large part in the damping.
		
		if (!defined($elasticMod)){
			switch ($material) {
				case "mono"     {$elasticMod	= $elasticModPSI_Nylon}
				case "fluoro"   {$elasticMod	= $elasticModPSI_Fluoro}
			}
		}
		$leaderElasticModsPSI	= $elasticMod*ones($diams);
		$leaderElasticModPSI	= $elasticMod; # For reporting.
		
		if (!defined($dampingMod)){
			switch ($material) {
				case "mono"     {$dampingMod	= $dampingModPSI_Dummy}
				case "fluoro"   {$dampingMod	= $dampingModPSI_Dummy}
			}
		}
		$leaderDampingModsPSI	= $dampingMod*ones($diams);
		$leaderDampingModPSI  	= $dampingMod;	# For reporting.
		
    } else {  # Get leader from menu. This call can't fail.
		
		print "Leader set from params\n";

		if ($updatingPanel){
			
			if (!$initialize){
				SwapLeaderFields(0); # Swap out only enabled fields.
				SwapLeaderFields(1);
			} # else, don't swap anything, just use the fields that were loaded.

=begin comment

			if ($initialize){	# Disable everything.  Copy nothing to storage.
				$leaderFieldsDisableInds	= sequence(7);
				@leaderFieldsDisable		= @main::leaderFields;
			}
			# Always swap the currently enabled fields (except menu) to level storage:
			SwapLeaderFields(0);
			
			# If we were reading from a file, swap the previous menu choice back in:
			if ($rps->{leader}{text} eq "---"){
				$rps->{leader}{text} = $rps->{leaderLevel}{text};
			}

=end comment

=cut

		}
		
        my $leaderText		= $rps->{leader}{text};
		pq($leaderText);
		if ($leaderText eq "---"){die  "Should always see a good leader menu item here.\n"}
		
        $leaderStr          = substr($leaderText,9); # strip off "leader - "
		my $testLeaderStr = $leaderStr;
		pq($testLeaderStr);
 
		switch($leaderStr) {
            
            case "level" {
			
				if ($updatingPanel) {
				
					# Swap all (non-menu) fields in from level:
					#???SwapLeaderFields(1);

					# Enable everybody (including the menu field):
					$leaderFieldsDisableInds	= zeros(0);
					@leaderFieldsDisable		= ();
					return 1;
				}
				
				$leaderLenFt            = POSIX::floor($rps->{leader}{lenFt});
				$leaderGrsPerFt         = $rps->{leader}{wtGrsPerFt}*ones($leaderLenFt);
				$leaderDiamsIn          = $rps->{leader}{diamIn}*ones($leaderLenFt);
				
				$leaderElasticDiamsIn   = $rps->{leader}{coreDiamIn}*ones($leaderLenFt);
				$elasticMod				= $rps->{leader}{coreElasticModulusPSI};
					 # For now, at least.
				
				$leaderDampingDiamsIn   = $leaderDiamsIn;
				$dampingMod				= $rps->{leader}{dampingModulusPSI};
			}

            case ["7ft 5x mono","10ft 3x mono"]       {
			
				if ($leaderStr eq "7ft 5x mono"){
					$leaderLenFt	= 7;
					$elasticMod		= 2.45e5;	# See Leader_10ft_3x_Umpqua_Mono
					$dampingMod		= 1e4;		# See Leader_10ft_3x_Umpqua_Mono
				} else {
					$leaderLenFt    = 10;
					$elasticMod		= 2.45e5;	# See Leader_10ft_3x_Umpqua_Mono
					$dampingMod		= 1e4;		# See Leader_10ft_3x_Umpqua_Mono
				}

				if ($updatingPanel){

					# Swap nothing back in from level:

					$rps->{leader}{lenFt}					= $leaderLenFt;
					$rps->{leader}{wtGrsPerFt}				= "---";
					$rps->{leader}{diamIn}					= "---";
					$rps->{leader}{coreDiamIn}				= "---";
					$rps->{leader}{coreElasticModulusPSI}	= $elasticMod;
					$rps->{leader}{dampingModulusPSI}		= $dampingMod;
					
					# Disable everything except the menu field:
					$leaderFieldsDisableInds	= sequence(6)+1;
					@leaderFieldsDisable		= @main::leaderFields[1 .. 6];	# Array slice.
					return 1;
				}

				if ($leaderStr eq "7ft 5x mono"){
					$leaderGrsPerFt         = pdl(0.086,0.117,0.290,0.775,0.958,0.958,0.958);
						# Computed from the measured diams using spGrav = 1.1;
					$leaderDiamsIn          = pdl(0.006,0.007,0.011,0.018,0.020,0.020,0.020);
				} else {
					$leaderGrsPerFt = pdl(0.153,0.194,0.240,0.290,0.405,0.613,0.776,0.865,0.958,0.958);
						# Computed from the measured diams using spGrav = 1.1;
					$leaderDiamsIn  = pdl(0.008,0.009,0.010,0.011,0.013,0.016,0.018,0.019,0.020,0.020);
				}
				
				$leaderElasticDiamsIn   = $leaderDiamsIn;
				$leaderDampingDiamsIn   = $leaderDiamsIn;
				
            }
            else    {die "\n\nDectected unimplemented leader text ($leaderStr).\n\nStopped"}
        }
		
		$leaderElasticModsPSI   = $elasticMod*ones($leaderLenFt);
		$leaderElasticModPSI	= $elasticMod; # For reporting.

		$leaderDampingModsPSI   = $dampingMod*ones($leaderLenFt);
		$leaderDampingModPSI  	= $dampingMod;	# For reporting.
    }

    if ($verbose>=3){pq($leaderGrsPerFt,$leaderDiamsIn)}
    if ($verbose>=3){pq($leaderElasticDiamsIn,$leaderElasticModsPSI,$leaderDampingDiamsIn,$leaderDampingModsPSI)}

    # Prepend the leader:
    $loadedLenFt += $leaderLenFt;
    
    $loadedGrsPerFt         = $leaderGrsPerFt->glue(0,$loadedGrsPerFt);
    $loadedDiamsIn          = $leaderDiamsIn->glue(0,$loadedDiamsIn);
    $loadedElasticDiamsIn   = $leaderElasticDiamsIn->glue(0,$loadedElasticDiamsIn);
    $loadedElasticModsPSI   = $leaderElasticModsPSI->glue(0,$loadedElasticModsPSI);
    $loadedDampingDiamsIn   = $leaderDampingDiamsIn->glue(0,$loadedDampingDiamsIn);
    $loadedDampingModsPSI   = $leaderDampingModsPSI->glue(0,$loadedDampingModsPSI);

    return $ok;
}
        

# Tippet variables:
our ($tippetStr);
our ($tippetLenFt,$tippetElasticModPSI,$tippetDampingModPSI);

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
        case "mono"     {$specGravity = 1.05; $tippetElasticModPSI = $elasticModPSI_Nylon; $tippetDampingModPSI = $dampingModPSI_Dummy}
        case "fluoro"   {$specGravity = 1.85; $tippetElasticModPSI = 4e5; $tippetDampingModPSI = $dampingModPSI_Dummy;}
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
    if ($verbose>=3){pq($tippetDiamsIn,$tippetElasticDiamsIn,$tippetElasticModsPSI,$tippetDampingDiamsIn,$tippetDampingModsPSI)}
	
    # Prepend the tippet:
    $loadedGrsPerFt         = $tippetGrsPerFt->glue(0,$loadedGrsPerFt);
    $loadedDiamsIn          = $tippetDiamsIn->glue(0,$loadedDiamsIn);
    
    $loadedLenFt += $tippetLenFt;
    
    $loadedElasticDiamsIn   = $tippetElasticDiamsIn->glue(0,$loadedElasticDiamsIn);
    $loadedElasticModsPSI   = $tippetElasticModsPSI->glue(0,$loadedElasticModsPSI);
    $loadedDampingDiamsIn   = $tippetDampingDiamsIn->glue(0,$loadedDampingDiamsIn);
    $loadedDampingModsPSI   = $tippetDampingModsPSI->glue(0,$loadedDampingModsPSI);
    
    PrintSeparator("Combining line components");
    
    if ($verbose>=3){print("\$loadedGrsPerFt = $loadedGrsPerFt\n\$loadedDiamsIn = $loadedDiamsIn\n")}
    if ($verbose>=3){print("\$loadedElasticDiamsIn = $loadedElasticDiamsIn\n\$loadedElasticModsPSI = $loadedElasticModsPSI\n\$loadedDampingDiamsIn = $loadedDampingDiamsIn\n\$loadedDampingModsPSI = $loadedDampingModsPSI\n")}

	# Figure the loaded volumes (used only in swing):
    my $loadedAreasIn2  = ($pi/4)*$loadedDiamsIn**2;
    $loadedVolsPerFt	= 12*$loadedAreasIn2;
		# number of cubic inches in a linear foot of line.
}



# Required package return value:
1;

__END__

=head1 NAME

RCommonLoad - Loads the line parts.

=head1 SYNOPSIS

use RCommonLoad;

=head1 EXPORT

LoadLine LoadLeader LoadTippet $loadedLenFt $loadedGrsPerFt $loadedDiamsIn $loadedElasticDiamsIn $loadedElasticModsPSI $loadedDampingDiamsIn $loadedDampingModsPSI $lineIdentifier $flyLineNomWtGrPerFt $leaderIdentifier $leaderStr $leaderLenFt $leaderElasticModPSI $leaderDampingModPSI $tippetStr $tippetLenFt $tippetElasticModPSI $tippetDampingModPSI $loadedVolsPerFt @lineFieldsDisable @leaderFieldsDisable);


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


