#!/usr/bin/perl

#############################################################################
## Name:			RCommon.pm
## Purpose:			Common code for the RHex project
## Author:			Rich Miller
## Modified by:	
## Created:			2014/10/20
## Modified:		2017/10/30
## RCS-ID:
## Copyright:		(c) 2017, 2019 Rich Miller
## License:			This program is free software; you can redistribute it and/or
##					modify it under the same terms as Perl itself
#############################################################################

# syntax:  use RCommon;

# Code common to the parts of the RHex project.

# Modification history:
#  14/03/12 - Began from RHexCastPkg
#  14/12/26 - Major update to include as much PDL as possible in supporting RHexStatic, RHexCast, and RHexReplot.

# Compile directives ==================================
package RCommon;

use constant DEBUG => 1;    # 0, or non-zero for debugging behavior, including higher level verbosity.  In particular the string "DEfunc_GSL" prints stepper outputs engendered by the stepper function DE() and "DEjac_GSL" prints jacobian outputs from the same source.  Actually, any true value for DEBUG except "DEjac_GSL" defaults to DEfunc_GSL".
# See https://www.perlmonks.org/?node_id=526948  This seems to be working, the export pushes DEBUG up the use chain.  I'm assuming people are right when they say the interpreter just expunges the constant false conditionals.

use warnings;
use strict;

use Exporter 'import';
our @EXPORT = qw( DEBUG $launchDir $verbose $debugVerbose $vs $rSwingOutFileTag $rCastOutFileTag $inf $neginf $nan $pi $massFactor $massDensityAir $airBlubsPerIn3 $kinematicViscosityAir $kinematicViscosityWater $waterBlubsPerIn3 $waterOzPerIn3 $massDensityWater $grPerOz $hexAreaFactor $hex2ndAreaMoment GradedSections GradedUnitLengthSegments StationDataToDiams DiamsToStationData DefaultDiams DefaultThetas IntegrateThetas ResampleThetas OffsetsToThetasAndSegs NodeCenteredSegs RodSegWeights RodSegExtraWeights FerruleLocs FerruleWeights RodKs GetValueFromDataString GetWordFromDataString GetArrayFromDataString GetQuotedStringFromDataString SetDataStringFromMat GetMatFromDataString Str2Vect BoxcarVect LowerTri ResampleVectLin ResampleVect SplineNew SplineEvaluate SmoothChar_Setup SmoothChar SmoothOnset SecantOffsets SkewSequence RelocateOnArc ReplaceNonfiniteValues exp10 MinMerge MaxMerge FindFileOnSearchPath PrintSeparator StripLeadingUnderscores HashCopy1 HashCopy2 ShortDateTime);

use Switch;
use Try::Tiny;
use Scalar::Util qw(looks_like_number);


use PDL;
    # Import main PDL module (see PDL.pm for equivalents).  In particular, imports PDL::Math, which redefines many POSIX math functions.  To get the original, call POSIX::aFunction.

use PDL::NiceSlice;     # Nice MATLAB-like syntax for slicing.
use PDL::AutoLoader;    # MATLAB-like autoloader.
use PDL::Options;     # Good to keep in mind. See RLM.

## Unsuccessful attempts to get a PDL spline:
#use PDL::GSL::INTERP;   # Spline interpolation, including deriv and integral.
#use PDL::Func;          # Includes an interpolation subroutine.   This almost works, but needs slatec for cubic.
#use PDL::Slatec;        # Needed for (hermite) cubic spline interpolation
#use PDL::Interpolate;
#use PDL::Interpolate::Slatec;

use Math::Spline;
    # Since I can't get PDL spline to work.  In any case, this provides trim access to splining.  See also RSpringFit.

use RUtils::Print;
use RUtils::Plot;


# Debugging param --------------------------------------------------------------

our $inf    = 9**9**9;
our $neginf = -9**9**9;
our $nan    = sin(9**9**9);
our $pi     = 4 * atan2(1, 1);

our $launchDir  = '';
our $verbose    = 1;
    # Unset to suppress debugging print statements.  Higher values trigger more output.  $verbose=0: errors, otherwise almost no printing at all; =1: warnings, execution stages; =2: file inputs, main run parameters, basic integrator step report; =3: main integrator computed variables; =4,5,...: more and more details.  NOTE that many subroutines start with a conditonal that enables or disables its own printing, at the level specified here.
our $debugVerbose = 4;

our $vs         = "\n";
    # Will (might) be maintained to "                          \r" so lines overwrite if $verbose<=1, else "\n" so they don't.  BUT, see RSink::OnVerbose.

our $rSwingOutFileTag = "#RSwingOutputFile";
our $rCastOutFileTag = "#RCastOutputFile";
# I put these here so that RHexReplot runs without needing the integrator installed.


sub PrintSeparator {
    my ($text,$minVerbose) = @_;
    
    if (!defined($minVerbose)){$minVerbose = 1}
    
    ## Verbosity sensitive separator print string.

    if (!$verbose or $verbose<$minVerbose){return}
    
    my $str = "";
    if ($verbose>=3){$str .= "\n"}  # Printing to the terminal.  Put a newline before the text.

    $str .= $text;
    if ($verbose==1){$str .= $vs}
#    if ($verbose==1){$str .= "\r"}
    else {$str .= " ========================\n"}
    
    print $str;
}


sub StripLeadingUnderscores {
    my ($str) = @_;
    
    my $char;
    for (my $ii=0;$ii<length($str);$ii++){
        if (substr($str,$ii,1) ne "_"){
            $str = substr($str,$ii);
            last;
        }
    }
    return $str;
}


# UNIX UTILITIES ===================================================================

sub FindFileOnSearchPath {
    my ($filename,$searchPath) =  @_;
	
	## Replaces the colon separator in the standard unix search paths with spaces, and makes a system call to find.
	
	pq($searchPath);
	my $strippedPath =~ s/:/ /g;
	pq($strippedPath);
	die;

	chomp(my $foundPath = `find $strippedPath $filename`);
	pq($foundPath);
	die;
}


# TEXT FILE UTILITIES ===================================================================


sub FindLabelInDataString {
    my ($data,$label,$direction) =  @_;
    
    ## Find a label in the data string.  Label must be at the start of the data or of a line, and directly followed by a colon.  $direction is one of the strings "first", "last".  Returns the index of the first character after the colon.
    
    if (!defined($direction)){$direction = "first"}

    # Look at first line by hand:
    my $foundAtZero = 0;
    my $searchStr   = $label.":";
    my $offset      = length($searchStr);
    if (substr($data,0,$offset) eq $searchStr){
        if ($direction == "first"){return $offset}
        else {$foundAtZero = 1}
    }
    
    $searchStr  = "\n".$searchStr;
    $offset  += 1;
    #pq($offset);
    
    #pq($label);
    
    my $index;
    # Both index and rindex return -1 if they fail to match.
    if ($direction ne "last"){
        $index = CORE::index($data,$searchStr);
        # Force use of built-in (PDL also has an index()).
        #print "first: index = $index\n";
        if ($index eq -1){return $index}    # Label not found.
    } else {
        $index = CORE::rindex($data,$searchStr,length($data)-1);
        #print "last: index = $index\n";
        if ($index eq -1){
            if (!$foundAtZero){return $index}
            else{return $offset-1}  # sic, to remove the previous increment for the newline.
        }
    }
    
    $index += $offset;
    #pq($index);
    
    return $index;
}

sub GetValueFromDataString {
    my ($data,$label,$direction,$minVerbose) =  @_;
    if (!defined($minVerbose)){$minVerbose = 4}
    
    ## Get a labeled single numerical value.  Label must be at the start of a line, and directly followed by a colon.  If the label is found but is not at a line start, an error message is printed.  Allowed value string as inclusive as possible (eg 2.3e5).  $direction is one of the strings "first", "last".  Failure to load return undef.
    
    my $outVal; # undefined.
    
    my $index = FindLabelInDataString($data,$label,$direction);
    if ($index == -1){
        if($verbose>=$minVerbose){print "GetValueFromDataString: label=\'$label:\' not found.\n"}
        return $outVal;
        
    }elsif ($index == -2){
        if($verbose>=$minVerbose){print "GetValueFromDataString: Found label=\'$label:\' but it was not at the beginning of a line. Associated data was ignored.\n"}
        return $outVal;
    }
    
    # Don't read past the next newline.
    my $endIndex = CORE::index($data,"\n",$index);
    #pq($endIndex);
    
    my $str;
    if ($endIndex eq -1){$str = substr($data,$index)}
    else {$str = substr($data,$index,$endIndex-$index)}
    #pq($str);
    
    my $ss;
    if ($str =~ m/^\s*(\S+)\s*#*.*$/mx){
        $ss = $1;
    }else{
        if($verbose>=$minVerbose){print "GetValueFromDataString: Found label=\'$label:\' but could not read data from that line.\n"}
        pq($str);
        return $outVal;
    }

    if (defined($ss) and $ss ne "" and looks_like_number($ss)){
        #        $$outVal = pdl(eval($ss));    Better to keep values in perl variables.
        $outVal = eval($ss);
        #pqf("%f",$outVal);
        #pqInfo($outVal);
    }else{
        if($verbose>=$minVerbose){print "GetValueFromDataString: Found label=\'$label:\' but data read does not look numerical.\n"}
        return $outVal;
    }

    return $outVal;
}


sub GetWordFromDataString {
    my ($data,$label,$direction,$minVerbose) =  @_;
    if (!defined($minVerbose)){$minVerbose = 4}
    
    ## Get a labeled string.  Label must be at the start of a line, and directly followed by a colon.  If the label is found but is not at a line start, an error message is printed. $direction is one of the strings "first", "last".  Failure to load return undef.
    
    my $outVal; # undefined.
    
    my $index = FindLabelInDataString($data,$label,$direction);
    if ($index == -1){
        if($verbose>=$minVerbose){print "GetFirstWordFromDataString: label=\'$label:\' not found.\n"}
        return $outVal;
        
    }elsif ($index == -2){
        if($verbose>=$minVerbose){print "GetFirstWordFromDataString: Found label=\'$label:\' but it was not at the beginning of a line. Associated data was ignored.\n"}
        return $outVal;
    }
    
    # Don't read past the next newline.
    my $endIndex = CORE::index($data,"\n",$index);
    #pq($endIndex);
    
    my $str;
    if ($endIndex eq -1){$str = substr($data,$index)}
    else {$str = substr($data,$index,$endIndex-$index)}
    #pq($str);

    my $ss;
    if ($str =~ m/^\s*(\S+)\s*#*.*$/mx){
        $outVal = $1;
    }else{
        if($verbose>=$minVerbose){print "GetValueFromDataString: Found label=\'$label:\' but could not read data from that line.\n"}
        pq($str);
        return $outVal;
    }
    #pq($outVal);

    return $outVal;
}

sub FindLabelLineInDataString {
    my ($data,$label,$direction) =  @_;
    
    ## Find a separate label line in the data string.  Label must be at the start of a line, and directly followed by a colon.  If the label is found but is not at a line start, an error message is printed.    There must be nothing else on the line except possibly a comment beginning with the hash character.  $direction is one of the strings "first", "last".  Returns the index of the first character after the colon.
    
    my $index = FindLabelInDataString($data,$label,$direction);
    if ($index < 0){return $index}
    
    # Don't read past the next newline.
    my $endIndex = CORE::index($data,"\n",$index);
    #pq($endIndex);
    
    my $str;
    if ($endIndex eq -1){return -3}     # No room for data.  Next line is eof.
    else {$str = substr($data,$index,$endIndex-$index)}
    #pq($str);
    
    # Check that there is nothing else, except possibly a comment on the label line:
    if ($str =~ m/^\s*#*$/mx){
        $index = $endIndex+1;
}else{
    $index = -2;    # Prohibited material found on the label line.
}
#pq($index);

return $index;

}


sub GetQuotedStringFromDataString {
    my ($data,$label,$direction,$minVerbose) =  @_;
    if (!defined($minVerbose)){$minVerbose = 4}
    
    ## Label must be at the beginning of a line, followed directly by a colon and possibly white space then a hash character introducing a comment, then a newline.  The next line must begin with a single quote, and the quoted material end with a single quote directly followed by a newline.  Only the material between the quotes is returned.  $direction is one of the strings "first", "last".  If undefined, defaults to "first".  Failure to load returns undef.
    
    my $index = FindLabelLineInDataString($data,$label,$direction);
    if ($index == -1){
        if($verbose>=$minVerbose){print "GetQuotedStringFromDataString: label=\'$label:\' not found.\n"}
        return undef;
    }elsif ($index == -2){
        if($verbose>=$minVerbose){print "GetQuotedStringFromDataString: Found label=\'$label:\' but it was not at the beginning of a line or there was prohibited material on the line. Associated data was ignored.\n"}
        return undef;
    }elsif ($index == -3){
        if($verbose>=$minVerbose){print "GetQuotedStringFromDataString: label=\'$label:\' was last line in file.  There was no room for data.\n"}
    }
    if ($index < 0){return undef}
    
    # So $index points to the beginning of the line after the label line.
    
    my $string = "";
    my $tStr = substr($data,$index,1);
    if (substr($data,$index,1) ne "\'"){return $string}
    $index++;
    
    my $endIndex = CORE::index($data,"\'\n",$index);
    if ($endIndex eq -1){return $string}
    
    return substr($data,$index,$endIndex-$index);
}

sub GetMatFromDataString {
    my ($data,$label,$direction,$minVerbose) =  @_;
    if (!defined($minVerbose)){$minVerbose = 4}
    
    ## Label must be at the beginning of a line, followed directly by a colon and a newline.  The next lines must be tab separated numbers, all with the same count.  Loading stops when this condition is not met.  $direction is one of the strings "first", "last".  If undefined, defaults to "first".  Failure to load returns empty pdl.
    
    my $mat = zeros(0);
    
    ## Label must be at the beginning of a line, followed directly by a colon and possibly white space then a hash character introducing a comment, then a newline.  The next line must begin with a single quote, and the quoted material end with a single quote directly followed by a newline.  Only the material between the quotes is returned.
    
    my $index = FindLabelLineInDataString($data,$label,$direction);
    if ($index == -1){
        if($verbose>=$minVerbose){print "GetMatFromDataString: label=\'$label:\' not found.\n"}
        return $mat;
    }elsif ($index == -2){
        if($verbose>=$minVerbose){print "GetMatFromDataString: Found label=\'$label:\' but it was not at the beginning of a line or there was prohibited material on the line. Associated data was ignored.\n"}
        return $mat;
    }elsif ($index == -3){
        if($verbose>=$minVerbose){print "GetMatFromDataString: label=\'$label:\' was last line in file.  There was no room for data.\n"}
    }
    if ($index < 0){return $mat}
    
    # So $index points to the beginning of the line after the label line.
    
    my $continue = 1;
    do {
        #pq $index;
        my $str;
        my $endIndex = CORE::index($data,"\n",$index);
        #pq $endIndex;
        if ($endIndex eq -1){$str = substr($data,$index)}
        else {$str = substr($data,$index,$endIndex-$index)}
        if ($str ne ""){
            try {
                my @aArray  = split(/\t/,$str);
                #print "STR TEST: str=$str\n";
                #print "aArray=@aArray\n";
                # Force an error if first array element isn't numeric:
                if (!looks_like_number($aArray[0])){die}
                
                my $count = @aArray;
                #pq $count;
                my $row;
                if ($count == 1)    {$row = $aArray[0]*ones(1)} # Force pdl
                else                {$row = pdl(@aArray)}
                #pq $row;
                $mat = $mat->glue(1,$row);
            } catch {
                $continue = 0;
            };
            $index = $endIndex+1;
        } else {$continue = 0}
        
    } while ($continue);
    
    return $mat;
}


sub SetDataStringFromMat {
    my ($mat,$label,$formatStr) =  @_;

    ## Write the label followed by a colon and newline, followed by the rows as tab separated lines.
    # If formatStr is passed, it must not include separator whitespace.
    
    my $formatStrPlusTab;
    if (defined($formatStr)){$formatStrPlusTab = $formatStr."\t"}
    
    my $string = "$label:\n";
    if ($mat->nelem == 0){return $string}
    
    $" = '	';	# Set the double-quoted string field separator to tab.

    my ($ncols,$nrows) = $mat->dims;
    if (!defined($nrows)){$nrows=1}
    for (my $ii=0;$ii<$nrows;$ii++){
        if (!defined($formatStr)){
            my @aRow = $mat(:,$ii)->list;
            $string .= "@aRow\n";
        }else{
            my @aRow = $mat(0:-2,$ii)->list;
            $string .= sprintf $formatStrPlusTab, $_  for @aRow;
            $string .= sprintf($formatStr,$mat(-1,$ii)->sclr)."\n";
        }
    }

    $" = " ";	# Restore the string separator to space.

#pq $string;
    return $string;
}




#### MATH UTILITIES  ==========================================================

sub ReplaceNonfiniteValues{
    my ($in,$val) = @_;
    my $nargs = @_;
    if ($nargs < 2){$val=0}
    
    my $isFinite = isfinite($in);
    my $count = $in->nelem;
    for (my $ii=0;$ii<$count;$ii++){
        if ($isFinite($ii)==0){$in($ii).=$val}
    }
    return $in;
}


sub exp10 {
    my ($n) = @_;
    return exp($n*log(10));
}

=for comment
# For some reason, perl (pdl?) provides this function but not exp10
sub log10 {
    my ($n) = @_;
    return log($n)/log(10);
}
=cut comment

sub MinMerge {
    my ($A,$B) = @_;
    my $comp = ($A<=$B);
    return $comp*$A+!$comp*$B;
}

sub MaxMerge {
    my ($A,$B) = @_;
    my $comp = ($A>=$B);
    return $comp*$A+!$comp*$B;
}

=for
sub Round {
    my ($a) = @_;
    if ($a == 0){return 0}
    if ($a > 0){return int($a+0.5)}
    if ($a < 0){return int($a-0.5)}
}
=cut

#### PERL UTILITIES  ==========================================================

# Replace this function with Data::Dump::dump(), preceeded by either eval or print.
=begin comment

sub PrintHash {
    my ($r_hash) = @_;

    my %testhash = %{$r_hash};
    my @names = keys %testhash;
    foreach my $nn (@names){
        print " $nn=$testhash{$nn}\n";
    }
}

=end comment

=cut



# These copy functions (1 or 2 levels) leave all the target pointers intact, which I need.

sub HashCopy1 {      # Require identical structure.  No checking.
    my ($r_src,$r_target) = @_;
    
    foreach my $l0 (keys %$r_target) {
        $r_target->{$l0} = $r_src->{$l0};
    }
}


sub HashCopy2 {      # Require identical structure.  No checking.
    my ($r_src,$r_target) = @_;
    
    foreach my $l0 (keys %$r_target) {
        foreach my $l1 (keys %{$r_target->{$l0}}) {
            $r_target->{$l0}{$l1} = $r_src->{$l0}{$l1};
        }
    }
}




# PDL UTILITIES ==============================================================

sub Str2Vect {
    my ($str) = @_;
    
    ## PDL initializes in very peculiar ways from a string of the form $str = "n0,n1,...nk".  This function always returns a PDL vector: [] if $str is undef or "", [n] if $str = "n", [n0,n1] if $str = "n0,n1", etc.
    
=for comment
    In particular, simply setting $pdl = pdl($str) gives:
    if $str is undef,
        def=
        pdl=0
        nelem=1
        dims=
        ndims=0
        empty=
    if $str = "",
        def=1
        pdl=Empty[0]
        nelem=0
        dims=0
        ndims=1
        empty=1
    if $str = "3",
        def=1
        pdl=3
        nelem=1
        dims=
        ndims=0
        empty=
    and if $str = "3,4",
        def=1
        pdl=[3 4]
        nelem=2
        dims=2
        ndims=1
        empty=
=cut comment

    my $vect;
    if (!defined($str) or $str eq ""){
        $vect = zeros(0)    
    } else {
        my @aArray = split(/,/,$str);
        $vect = pdl(@aArray);
        if (scalar(@aArray)==1){$vect=$vect->flat}
    }
    return $vect;
}


sub BoxcarVect {
    my ($in,$num) = @_;
    
#pq($in,$num);

    if ($num < 2){return $in}

        my $pre     = POSIX::ceil($num/2);
        my $post    = $num-$pre;
        
        my $out = (ones($pre)*$in(0))->glue(0,$in)->glue(0,ones($post)*$in(-1));        
        $out = cumusumover($out);
        $out = $out($num:-1)-$out(0:-$num-1);
        $out /= $num;
#pq $out;
        
        return $out;
}

sub LowerTri {
    my ($n,$includeDiagonal,$bandWidth) = @_;
    
    ## Prepare lower tri matrix, or if band width is passed, a banded lower triangular.
    
    my $mat = sequence($n);
    $mat = $mat - $mat->transpose;    # PDL dummies both pieces!
    
    my $tmat;
    if (defined($bandWidth)){$tmat = $mat > -$bandWidth}
    
    if ($includeDiagonal) {$mat = $mat<=0}
    else {$mat = $mat<0}
    
    if (defined($bandWidth)){$mat *= $tmat}
    
    return $mat;
}


sub ResampleVectLin {
    my ($inVals,$outFractLocs) = @_;
    
    # Cruder but more stable than ResampleVect() which has cubic spline liabilities.
    my $maxIndex = ($inVals->nelem)-1;
    
    my $outLocs = $outFractLocs * $maxIndex;
    
    my $outInds = $outLocs->long;
    #pq($outLocs,$outInds);
    
    my $outRems = $outLocs-$outInds;
    #pq($outRems);
    
    my $extendedInVals = $inVals->glue(0,$inVals(-1));
    my $outVals = (1-$outRems)*$extendedInVals($outInds) + $outRems*$extendedInVals($outInds+1);
    
    #pq($outVals);
    return $outVals;
}

sub ResampleVect {
    my ($inVals,$arg2,$arg3) = @_;
    
    ## A wrapper for Spline.
    # usage:    $outVals = ResampleAtRelLocs($inVals,[$inLocs,]($outRelLocs(pdl)|$outCount));
    #   If there are only two args, and the second is not a perl scalar, then it must be a pdl that contains RELATIVE locations (that is, in the range [0,1]).  IT IS THE CALLER'S BUSINESS TO GET THIS RIGHT.

    my $numArgs = @_;
    my ($inLocs,$outRelLocs);
    
    if ($numArgs == 2){
        $inLocs  = sequence($inVals);
        $outRelLocs = (ref(\$arg2) eq "SCALAR") ? sequence($arg2)/($arg2-1) : $arg2;
    } elsif ($numArgs == 3){
        $inLocs  = $arg2;    
        $outRelLocs = (ref(\$arg3) eq "SCALAR") ? sequence($arg3)/($arg3-1) : $arg3;
    } else {
        die "At least 2 args must be passed.\nStopped";
    }
    
    # Relativize inLocs (I'm assuming the values increase with index):
    $inLocs -= sclr($inLocs(0));
    $inLocs /= sclr($inLocs(-1));
            
    my $spline      = SplineNew($inLocs,$inVals);
    my $outVals     = SplineEvaluate($spline,$outRelLocs);

    return $outVals;
}


sub SplineNew {
    my ($xs,$ys) = @_;

    ## I couldn't get PDL spline to work, so am faking it.
    
    my @aXs = $xs->list;
    my @aYs = $ys->list;
    my $tSpline = Math::Spline->new(\@aXs,\@aYs);

    return $tSpline;
}


sub SplineEvaluate {
    my ($spline,$xs) = @_;
    
    my $ys = zeros($xs);
    for (my $ii=0;$ii<$xs->nelem;$ii++) {
        $ys($ii) .= $spline->evaluate($xs($ii)->sclr);
    }    

    return $ys;
}


my $smoothCharSpline;

sub SmoothChar_Setup {
    my ($count) = @_;
    
    ## Prepare for subsequent calls to SmoothChar() below.
    
    my $xs = sequence($count)**2;   # Want to sample more heavily near the bounds.
    $xs *= 1/$xs(-1);
    $xs = 1-$xs(-1:0);    # Flip.
    
    my $dxs = $xs(1:-1)-$xs(0:-2);
    my $ys = exp(-1/(1-$xs**2));
    # The usual smooth "bump" function.  All derivatives exist and are zero at 0 and 1.
    
    $ys = $ys(0:-2)*$dxs;       # Forget the last value, which is zero.
    $ys = cumusumover($ys);
    $ys = (-$ys(-1:0))->glue(0,pdl(0))->glue(0,$ys);   # Symmetrize.
    $ys *= 1/(2*$ys(-1));
    
    $ys += 0.5;                     # Normalize.
    $ys = $ys(-1:0);                            # Flip.
    
    $xs = $xs(1:-1);
    $xs = (-$xs(-1:0))->glue(0,pdl(0))->glue(0,$xs);   # Symmetrize.
    
    #Plot($xs,$ys,"SmoothChar","SmoothChar_Setup");
    
    $smoothCharSpline = SplineNew($xs,$ys);
}


sub SmoothChar {
    my ($xs,$lb,$ub) = @_;
    
    ## For numbers <= than $lb returns 1, for numbers >= $ub returns 0, and smoothly interpolates numbers between.
    
    my $nargs = @_;
    if ($nargs<3){
        $lb = 0;
        $ub = 1;
    }
    
    $xs = $xs->copy;
    
    # Spread the interval [$lb,$ub] onto [-1,1]:
    $xs -= $lb;
    $xs *= 2/($ub-$lb);
    $xs -= 1;
    
    # Collapse to bounds:
    $xs = ($xs<-1)*(-1) + ($xs>1) + ($xs>=-1)*($xs<=1)*$xs;
    
    my $ys = SplineEvaluate($smoothCharSpline,$xs);
    
    #Plot($xs,$ys,"SmoothChar_call");
    return $ys;
}


sub SmoothOnset {
    my ($xs,$lb,$ub) = @_;
    
    ##  Integrates smooth char.  Thus, smoothly connects the zero function to the left of $lb  to a linear function of slope 1 above $ub in such a way that the transition is always concave up.  Note that this means the functional values above $ub are a constant amount below the linear function through the origin with slope 1.  For one sided Hook's Law applications this is probably the behavior we really want.
    
    my $nargs = @_;
    if ($nargs<3){
        $lb = 0;
        $ub = 1;
    }
    
    #pq($xs,$lb,$ub);
    
    my $xns = $xs->copy;
    
    # Normalize the interval [$lb,$ub] onto [0,1]:
    $xns -= $lb;
    $xns *= 1/($ub-$lb);
    #pq($xns);
    
    # Collapse to bounds:
    my $xcns = ($xns>1) + ($xns>=0)*($xns<=1)*$xns;
    #pq($xcns);
    
    my $ys = $xcns**2/2;
    #pq($ys);
    
    #my $ys = SplineEvaluate($smoothOnsetSpline,$xns) + ($xns>=1)*($xs-$ub);
    #    $ys += ($xns>=1)*($xs-$ub);
    $ys += ($xcns>=1)*($xns-1);
    $ys *= $ub-$lb;
    #pq($ys);
    
    #Plot($xs,$ys,"SmoothOnset_call");
    return $ys;
}



sub SecantOffsets {
    my ($r,$l,$xs) = @_;
    
    #pq($r,$l,$xs);
    
    my $rSign = $r <=> 0;
    $r = abs($r);
    
    if ($l > 2*$r){die "ERROR: The secant length must be no greater than twice the radius\nStopped"}
    
    ## Cut a circle of radius $r with a secant of length $l.  For each $x measured from one end of the secant line, get the distance perpendicular to the line from the x point to the circle.
    
    my $k = sqrt($r**2 - ($l/2)**2);
    my $ys = sqrt($r**2 - (($l/2)-$xs)**2) - $k;
    $ys *= $rSign;
    
    #pq($ys);
    return $ys;
}


sub SkewSequence {
    my ($lb,$ub,$skewness,$xs) = @_;
    
    #print "IN SKEW ...\n";
    
    ## For positive skew exponent, smoothly skews the values away from the lower bound, leaving the bounds in place; negative toward the lower bound; zero is noop.
    
    if ($ub<=$lb){die "ERROR: Lower bound must be strictly less than the upper bound\nStopped"}
    
    my $txs = ($xs-$lb)/($ub-$lb);
    #pq($txs);
    #    Plot($txs);

    if (any($txs < 0) or any($txs > 1)){die "ERROR:  All values must be between the bounds.\nStopped"}
    
    my $tExp    = ($skewness>=0) ? 1+$skewness : 1/(1-$skewness);
    #pq($tExp);
    
    my $tys     = 1-(1-$txs**$tExp)**(1/$tExp);
    #pq($tys);
    #Plot($txs,$tys,"tys");

    $txs = $tys*($ub-$lb) + $lb;
    #pq($txs);
    #Plot($xs,$txs,"final");
    
    return $txs;
}


sub RelocateOnArc {
    my ($segLens,$curvature,$offsetTheta) = @_;
    
    ## Take the initial segment configuration as straight along the x-direction, deflected toward positive y by $offsetTheta, and then relocated onto an arc having the desired curvature, without changing the deflection angle between the initial and final nodes.  Positive curvature produces an arc that is convex toward positive x.

    #pq($segLens,$curvature,$offsetTheta);
    
    my ($dxs,$dys);
    if ($curvature == 0){
        $dxs = $segLens*cos($offsetTheta);
        $dys = $segLens*sin($offsetTheta);
    }else{
        if ($offsetTheta<0){$curvature *= -1}
        my $totalLen    = sum($segLens);
        my $radius      = 1/$curvature;
        my $curveSign   = $curvature <=> 0;
        
        $radius = abs($radius);
        if ($radius < $totalLen/$pi){die "Line initial curvature too large.\nStopped"}
        
        my $centerThetas    = 2*asin($segLens/(2*$radius));
        $centerThetas       *= $curveSign;
        
        my $relThetas = $centerThetas/2;
        my $cumThetas = cumusumover($centerThetas);
        $cumThetas = zeros(1)->glue(0,$cumThetas);
        
        my $totalThetas = $cumThetas(-1);
        $cumThetas += $offsetTheta - $totalThetas/2;
        
        my $xs = $radius*sin($cumThetas);
        my $ys = $radius*(1-cos($cumThetas));
        
        $dxs = $xs(1:-1)-$xs(0:-2);
        $dys = $ys(1:-1)-$ys(0:-2);
        
        if ($curveSign < 0){
            $dxs *= $curveSign;
            $dys *= $curveSign;
        }
        
    }
    
    return ($dxs,$dys);
}



## PHYSICAL AND MATHEMATICAL CONSTANTS, ETC ======================================



# I calculate in inches-ounces-seconds-radians, the so called "ROSI", or "ISOR" system.  That was probably a mistake.  But see http://www.lastufka.net/lab/refs/html/ptunits.htm, where it is all worked out.

# We need MASS rather than WEIGHT in the dynamical calculations.

# FORCE, MASS, and GRAVITY:
    # Put a 1 lbf (weight, force) object on a spring scale and it depresses it some amount, 1 DY.  Drop the object and it accelerates at g ft/sec2, where g ("standard gravity (ie, sort of at the earth's surface), not to be confused with G ("big G", the "universal gravitational constant) is measured to be 32.174.  The mass of the object, as used in F=ma (or F=mg here) is therefore 1 lbm (a unit of mass).  However, another, perhaps computationally more useful, unit of mass would be the one that produces an acceleration of 1 ft/sec2.  This is called the slug, and its value is g times 1 lbm.  Note that there is nothing really universal about the slug, because the force measure still depends on the (cosmically accidental) value of g. However, since we are accustomed to force measured in lbf, computations in lbf, slugs, ft, and secs are appropriate.

    # What about dealing with forces in ounces (ozf) and length units of inches?  To begin, the ounce (weight) object is defined as 1/16th of the pound object.  It depresses the Hook's Law scale 1/16th as much as the pound object does.  Its mass (1 ozm) must be 1/16th of 1 lbm.  (To Newtonian approximation, mass is just counting baryons.)  The unit of mass analogous to the slug would be the one that is accelerated to 1 in/sec2 by a  1 ozf -- so, 1 ozm times 32.174 * 12 = 386.088.  Dare I call this mass unit the "slounce".  1 slounce is 3/4 of a slug -- which is surprisingly large.  

    # OLD WAY - Quicker:
        # G = 32.174 ft/s2, wt/G = mass in slugs.  1 lb force acting on 1 slug produces an acceleration of 1 ft/sec2.  We are working in oz, inch units.  Weight here is already in units of ounces.  So I think we want to just convert G into inches, ie multiply it by 12.


# Let the "blub" be the COHERENT unit of mass in the (oz-weight,in,sec) system of units.  See https://en.wikipedia.org/wiki/Coherence_(units_of_measurement . In particular, when density is expressed in blubs/in^3, frictional force will be expressed in oz-weight units, and so will be directly comparable (addable) to gravitational force (also naturally expressed in oz-weight units).

my $kilograms2slugs = 0.06852;
my $slugs2blubs = 16/12;
my $kilograms2blubs = $kilograms2slugs*$slugs2blubs;
my $meters2inches = 39.37;
my $waterKgPerM3 = 1000;
our $waterBlubsPerIn3 = $waterKgPerM3*$kilograms2blubs/$meters2inches**3;


our $lbsPerFt3toOzPerIn3 = 0.00926;
our $grPerOz = 437.5;

our $massFactor = 1/(12*32.174);             # Convert ozf to slounces.
    # Acceleration of gravity in in/sec^2

# At 70 °F and 14.696 psi, the density of dry air is 0.074887 lbm/ft3.
# or 2.329 x 10-3 slugs/ft3.
# At sea level and at 15°C , the density of air is 1.275 kg/m3.
#!! https://en.wikipedia.org/wiki/Coherence_(units_of_measurement)
# https://en.wikipedia.org/wiki/Centimetre%E2%80%93gram%E2%80%93second_system_of_units, especially electro-magnetism.
# https://en.wikipedia.org/wiki/Slug_(unit)

# Density, or better volumetric mass density (== mass/unit_volume).  Specific gravity (or relative density) is the ratio of the mass density of the substance to that of a control substance, usually water at its densest (liquid) state.  Note that weight/unit_volume is called specific weight.
# https://en.wikipedia.org/wiki/Density.

our $massDensityAir         = 1.771e-8;      # slounces/in3.
my $airKgPerM3              = 1.28;
our $airBlubsPerIn3         = $airKgPerM3*$kilograms2blubs/$meters2inches**3;

our $airSpecificGravity     = 0.00120;
our $airOzPerIn3    = 0.0006934;
# At 70 °F and 14.696 psi, dry air has a density of 0.074887 lb/ft3.
# At 15ºC, air density is 1.225 kg/m^3

our $kinematicViscosityAir   = 2.36e-2;      # in2/sec, at 70 deg F.
# Kinematic viscosity of air is 1.64 x 10-4 ft2/sec. http://www.engineeringtoolbox.com/air-absolute-kinematic-viscosity-d_601.html

our $waterSpecificGravity   = 0.99802;
our $waterOzPerIn3  = 0.578;
# So, water = 1 at 4ºF (max density temp), and weighs 62.424 lbs/ft^3.  At 70ºF, the cubic foot weighs 62.300 lbs, giving a density of 0.99802.
# At 15ºC, water density is 999.1026 kg/m^3, Ideally at 4ºC it would be 1000kg/m^3, but due to a problem with standardization it is 999.9720.  (Possibly it is a bit denser a bit off 4º.)

our $massDensityWater       = 1.47e-5; #### Check me !!!!

our $kinematicViscosityWater = 1.512e-3;
# Kinematic viscosity of water at 20º C is (1.0035 m2/s)*10-6
# At 70º F, (1.0503 ft2/s)*10-5, = 151.24 * 10-5 in^2/sec.  https://www.engineeringtoolbox.com/water-dynamic-kinematic-viscosity-d_596.html




# See especially W.Schott (http://www.powerfibers.com/BAMBOO_IN_THE_LABORATORY.pdf).
 
# Bamboo is commonly said to weight about 350Kg/M3, which I convert to 22lbs/cu.ft or 0.20oz/in3.  BUT THIS IS WRONG!  My own observation is that dry planed bamboo splines nearly sink in the wetting tube, and by the next day they have sunk.  Water density is 62.4 PdCuFt, so I recommend using just a bit less than this.  My weighting of a 1/4" diam glued test segment showed just about 0.6 OzCuIn.  Hexrod says Garrison used 0.668.  Schott generally agrees.  That is quite a bit heavier than water!  The rod builders estimate that bamboo's elastic modulus is about 5*10^6 psi and maybe a bit more near the tip where the power fibers dominate.  There are 437.5 grains per ounce.  Note that an "n-weight line" is n*grains/foot.  So, in particular, the definitional 30' loop weighs n*30 grains for a 1-weight rod.  The plotted Cortland weights seem to be a bit less than this!  Specific ferrule weights are tabulated in Hexrod site documentation (see sub CalcFerruleWts).  I account for the weights of varnish and guides with a single multiplier of the diam at each node (see CalcVarnishAndGuidesWeights).  Make a wild guess

our $hexCircFactor = 2*sqrt(3); # Times flat-to-flat D.
our $hexAreaFactor = sqrt(3)/2; # Times flat-to-flat D squared.

our $hex2ndAreaMoment = 5*sqrt(3)/144;    # = 0.060, or ~1/16.6, compared to 1/12 for a square.
    # W.Schott (http://www.powerfibers.com/BAMBOO_IN_THE_LABORATORY.pdf)confirms this formula, and the 4th power of the flat-to-flat distance in the formula for I.  Usually called "2nd moment of area".


# See Hexrod documentation for a specific tabulation for Super Z ferrules.  For undocumented smaller diameters I use the minimum documented value.
	my @ferruleWtsSuperZ;
	@ferruleWtsSuperZ[0..7] =
       (0.120,0.120,0.120,0.120,0.120,0.120,0.120,0.120);
	@ferruleWtsSuperZ[8..32] =
       (0.120,0.135,0.162,0.194,0.225,0.271,0.328,0.358,0.397,0.437,
        0.477,0.516,0.556,0.595,0.633,0.672,0.711,0.749,0.787,0.825,
        0.863,0.900,0.938,0.975,1.012);
	@ferruleWtsSuperZ[33..40] =
       (1.012,1.012,1.012,1.012,1.012,1.012,1.012,1.012);
			
	if ($verbose >=4){print "FerruleWts:\n\tferruleWtsSuperZ=@ferruleWtsSuperZ\n"}
				    


sub GradedSections { my $verbose = 0?$verbose:0;
    my ($diams,$fiberGradient,$maxWallThickness) = @_;
    
    ## Calculates power fiber count 2nd moments of hexagonal cross-sections under the assumption that the number of power fibers on a culm radius decreases linearly from a maximum at the enamel to a lower number at the pith.  As usual, diams is the flat-to-flat distance, and the integration for each triangular segment starts at 0 at the surface and continues inward to the point where either the max wall thickness is reached or the fiber count becomes zero.
    
    # G is in 1/inches to drop from 1 to 0.  Higher numbers soften the rod generally, but stiffen the tip relative to the base.
    
    # It is the conceit of this function that only the power fibers contribute to the elasticity, and the internal damping.

    my $nargs = @_;
    #pq($nargs,$diams,$fiberGradient,$maxWallThickness);
    if ($nargs < 2) {$fiberGradient = 0}        # Zero is uniform pf distribution.
    if ($nargs < 3) {$maxWallThickness = 1}     # Anything larger than the max half-diam is noop.
    
    # Short names to use in the formula:
    my $H = $diams/2;
    my $G = $fiberGradient;
    
    my $Hmin = 0;
    if ($G<0 or $maxWallThickness<0){print "WARNING - GradedSections:  G and maxWallThickness must be non-negative."}
 
    if ($G!=0 and $maxWallThickness>1/$G){$maxWallThickness = 1/$G}
    if ($maxWallThickness){
        my $adjust = $H>$maxWallThickness;
        $Hmin = $adjust*($H-$maxWallThickness);   # Zero if not adjusted.
    }else{$Hmin = zeros($H)}
    if ($verbose>=3){pq($maxWallThickness,$H,$Hmin)}
    
    my $COUNT_TEST = 0;
    if ($COUNT_TEST){
        pq($H,$Hmin);
        # Figure power fiber count.  Normalized so as to equal the area if G = 0:
        my $pfCounts = 2*sqrt(3)*(1-$G*$H)*($H**2-$Hmin**2)+(4/sqrt(3))*$G*($H**3-$Hmin**3);
        my $pfCounts1 = 2*sqrt(3)*( (1-$G*$H)*($H**2-$Hmin**2)+(2/3)*$G*($H**3-$Hmin**3) );
        my $pfCounts2 = 2*sqrt(3)*( ($H**2-$Hmin**2)-(1/3)*$G*($H**3-$Hmin**3) );
        pq($pfCounts,$pfCounts1,$pfCounts2);
        
        # Extreme approximation of moments calculation:
        my $test = $pfCounts(1:-1)/($pfCounts(0:-2)+$pfCounts(1:-1));
        pq($test);
        print "\n";
    }
    ## These are the 1st moments, we want the second for computing the rod spring constants.
    #    my $pfMoments = (8/(3*sqrt(3)))*(1-$G*$H)*($H**3-$Hmin**3)+(2/sqrt(3))*$G*($H**4-$Hmin**4);
    
    my $effective2ndMoments = (5/(3*sqrt(3)))*(1-$G*$H)*($H**4-$Hmin**4) +
                            (4/(3*sqrt(3)))*$G*($H**5-$Hmin**5);
    
    if ($verbose>=1){pq($effective2ndMoments)}
    
    return $effective2ndMoments;
}



sub GradedUnitLengthSegments { my $verbose = 0?$verbose:0;
    my ($diams,$fiberGradient,$maxWallThickness) = @_;
    
    ## Return values used for figuring segment weights and moments.  Calculates average power fiber counts (effective volumes) and longitudinal (effective) moments for uniformly tapering, UNIT LENGTH segments under same assumptions as GradedSections().  The quotients of the moments by the volumes give the unit length segment cg's. Computed for segLens = 1, but subsequent multiplication by the actually segLens give the right results.  Called with just the first argument, and subsequently using the appropriate section area correction factor, this function would work for the line too.
    
    # Max wall thickness greater than the largest rod half-diameter means no restriction on wall thickness, thus no hollow core.  However, the condition that the fiber count not go negative forces max wall thickness to be set to 1/G unless it already is less:
    
    my $nargs = @_;
    if ($nargs < 2) {$fiberGradient = 0}        # Zero is uniform pf distribution.
    if ($nargs < 3) {$maxWallThickness = 1}     # Anything larger than the max half-diam is noop.
    
    # Short names to use in the formula:
    my $H = $diams/2;
    #pq $H;
    my $G = $fiberGradient;
    
    my $Hmin = 0;
    if ($G<0 or $maxWallThickness<0){print "WARNING - GradedUnitLengthSegments:  G and maxWallThickness must be non-negative."}

    if ($G!=0 and $maxWallThickness>1/$G){$maxWallThickness = 1/$G}
    if ($maxWallThickness){
        my $adjust = $H>$maxWallThickness;
        $Hmin = $adjust*($H-$maxWallThickness);   # Zero if not adjusted.
    }else{$Hmin = zeros($H)}
    
    my $minDensity = 1;
    if ($G){$minDensity = 1-$G*$maxWallThickness}
    
    # NOTE:  All formulas below must be multiplied by a hex factor, which will be done just before return.
    my $hexFactor = 2*sqrt(3);
    
    if ($verbose>=3){pq($G,$maxWallThickness,$H,$Hmin,$minDensity,$hexFactor)}
    
    # Figure average power fiber count of the segments.  Normalized so as to equal the area if G = 0 (that is, density = 1).  The formulas immediately below give quantities gotten by integrating all the way from the rod surface to the centerline, starting with density equal 1 at the surface:
    ## temp
    my $H0 = $H(0:-2);
    my $H1 = $H(1:-1);
    #pq($H0,$H1);
    
    #        my $pfAvCounts1 = (sqrt(3)/$DH)*((2/3)*($H0**3-$H1**3) - (1/6)*$G*($H0**4-$H1**4));
    # H0 is the UPPER bound of the integral, H1 the LOWER!
    my $effectiveVolumes =  (
                        (1/3)*($H1**2 + $H1*$H0 + $H0**2)
                        - ($G/3)*(1/4)*($H1**3 + $H1**2*$H0 + $H1*$H0**2 + $H0**3)
                    );
                    # Note: symmetric form.
    
    my $effectiveMoments = (
                        (1/12)*(3*$H1**2 + 2*$H1*$H0 + $H0**2)
                        - ($G/3)*(1/20)*(4*$H1**3 + 3*$H1**2*$H0 + 2*$H1*$H0**2 + $H0**3)
                    );
                    # Note: non-symmetric in H0, H1.
    

    #pq($effectiveVolumes,$effectiveMoments);

    if (any($Hmin>0)){

        # If there is a hollow core, we need to subtract from the above formulas quantities corresponding to the part of the integrals that went from the inner surface of the wall to the centerline.  The hollow core typically only exists along a part of the rod centerline (We assume here that the diams are monotonically decreasing).  Because the previous formulas assumed density 1 at the surface, the subtracted quantities must be adjusted to match the density at the inner wall surface:
        
        my $inds    = which($Hmin>0);
        my $nCoreSegs = $inds->nelem -1;
        
        my $J  = $Hmin($inds);
        
        if ($J->nelem > 1){

            my $J0 = $J(0:-2);
            my $J1 = $J(1:-1);
            
            # The density correction only applies to the non-gradient terms.
            
            my $effectiveCoreCounts =  (
                                    $minDensity*(1/3)*($J1**2 + $J1*$J0 + $J0**2)
                                    - ($G/3)*(1/4)*($J1**3 + $J1**2*$J0 + $J1*$J0**2 + $J0**3)
                                );

            
            my $effectiveCoreMoments = (
                                    $minDensity*(1/12)*(3*$J1**2 + 2*$J1*$J0 + $J0**2)
                                    - ($G/3)*(1/20)*(4*$J1**3 + 3*$J1**2*$J0 + 2*$J1*$J0**2 + $J0**3)
                                );

            $effectiveVolumes(0:$nCoreSegs-1)   -= $effectiveCoreCounts;
            $effectiveMoments(0:$nCoreSegs-1)   -= $effectiveCoreMoments;

            #pq($effectiveCoreCounts,$effectiveCoreMoments);
            #pq($effectiveVolumes,$effectiveMoments);
        }
        
        if ($J->nelem < $H->nelem){
            # There still may be a cone core in the next outboard segment:
            my $J0 = $J(-1);    # The nominal J1 = 0.
            my $K1 = $maxWallThickness-$H($nCoreSegs+1);  # This case only arises if max wall thickness < J0.
            my $crossover = $J0/($J0+$K1);

            my $effectiveConeCounts = $crossover * (
                                                $minDensity*(1/3)*($J0**2)
                                                - ($G/3)*(1/4)*($J0**3)
                                            );
                # The factor $crossover accounts for the reduced volume due to the shorter cone height.

            my $effectiveConeMoments = $crossover**2 * (
                                                $minDensity*(1/12)*($J0**2 )
                                                - ($G/3)*(1/20)*($J0**3)
                                            );
               # Sic, $crossover**2, one factor due to the reduced volume and the other due to the shorter lever arm relative to the unit length segment.

            $effectiveVolumes($nCoreSegs)    -= $effectiveConeCounts;
            $effectiveMoments($nCoreSegs)   -= $effectiveConeMoments;

            #pq($nCoreSegs,$J0,$K1,$crossover,$effectiveConeCounts,$effectiveConeMoments);
            #pq($effectiveVolumes,$effectiveMoments);
        }
    }

    $effectiveVolumes    *= $hexFactor;
    $effectiveMoments   *= $hexFactor;

    if ($verbose>=3){pq($effectiveVolumes,$effectiveMoments)}
    
    return ($effectiveVolumes,$effectiveMoments);
}




#### RHEX SPECIFIC FUNCTIONS  =====================================================

sub StationDataToDiams {
	my ($statXs,$statDiams,$actionLength,$numNodes) = @_;

    ## Remember, station 0 is at the tip, x_coord 0 is at the butt end of the action.

    my $spline  = SplineNew($statXs,$statDiams);

    my $xs      = $actionLength*sequence($numNodes)/($numNodes-1);
    $xs         = $xs(-1:0);
    my $diams   = SplineEvaluate($spline,$xs);
        
    return $diams;
}


sub DiamsToStationData {
	my ($diams,$rodLength,$actionLength) = @_;

    ## Ideally, for stations in the handle, we should match the horizontal tangent boundary condition at the handle end action boundary.  Constant interpolation is quite noticeably bad, so I'll try linear, using the data from diams.  Naturally enough, on a linear taper, this works (nearly) perfectly:

    my $deltaStation        = 5;  # The standard 5 inches.
    my $numStations         = POSIX::ceil($rodLength/$deltaStation)+1;
    
    my $numNodes    = $diams->nelem;
    my $segLen      = $actionLength/($numNodes-1);
    my $numExtNodes = POSIX::ceil(($rodLength-$actionLength)/$segLen);

    my $deltaX      = $actionLength/($numNodes-1);
    my $inds        = sequence($numNodes);
    $inds           = $inds->glue(0,($inds(-1)->sclr+$numExtNodes)*ones(1));
        # Sic, just add the last one.
    my $tXs         = $deltaX*$inds;

    my $tDiams      = $diams(-1:0)->copy;     # Want to start with tip (station 0).
    my $handleSlope = ($tDiams(-1)-$tDiams(-2));
    $tDiams = $tDiams->glue(0,($tDiams(-1)->sclr+$handleSlope*$numExtNodes)*ones(1));

    my $spline      = SplineNew($tXs,$tDiams);
    my $statXs      = $deltaStation*sequence($numStations);
    my $statDiams   = SplineEvaluate($spline,$statXs);
 
    return ($statXs,$statDiams);	
}


sub DefaultDiams {
	my ($numNodes,$diam0,$diamTip) = @_;
    
	my $delta   = ($diam0-$diamTip);
    my $diams   = sequence($numNodes)/($numNodes-1);
    $diams      = $diams(-1:0);
    $diams *= $delta;
    $diams += $diamTip;
    
    return $diams;
}


sub DefaultThetas {
	my ($numNodes,$totalTheta) = @_;
    
    my $nargs = @_;
    if ($nargs < 2){$totalTheta = 3.14159/4}

    my $dTheta = $totalTheta/($numNodes-1);
    my $thetas  = $dTheta*ones($numNodes);	    
    $thetas(-1) .= 0;
        # The tip node is never bent.
	    
    return $thetas;
}


# Resampling discrete functions that represent quantities INTEGRATED over segments takes some finesse, and details vary depending on what is represented.  The following functions resample appropriately for the purposes of the dynamics simulated here.  Input arguments are pdls or perl scalar numbers and outputs are pdls:

sub IntegrateThetas {
    my ($inThetas,$inSegLens) = @_;
    
    ## usage:    $outThetas = IntegrateThetas($inThetas,[$inSegLens]);
    ##          $inSegLens is a vector or a constant.  If it is omitted, it will be set to 1;
    ## As is our usual convention, inThetas is to be passed with 0 at the tip.  If it is a vector, inSegLens must be one index shorter than inThetas.
    
    if (!defined($inSegLens)){$inSegLens = 1}
    
    # The thetas are angles of a segment relative to the previous segment.  Think of each theta being applied at the START of its segment, and producing a displacement at the segment end.  These accumulate to produce a sequence of cartesian coordinates.  (This is just what we do for the rod in Calc_Qs().)
        
    my $inCumThetas = cumusumover($inThetas(0:-2));  # Tip 0 unused.
    
    my $dXs = zeros(1)->glue(0,$inSegLens*sin($inCumThetas));
    my $dYs = zeros(1)->glue(0,$inSegLens*cos($inCumThetas));
    
    my $Xs = cumusumover($dXs);
    my $Ys = cumusumover($dYs);

    return ($Xs,$Ys);
}


sub ResampleThetas {
    my ($inThetas,$arg2,$arg3) = @_;

    ## usage:    $outThetas = ResampleThetas($inThetas,[$inSegLens,]($outSegLens(pdl)|$outNodeCount));
    ##           If $inSegLens is omitted, the lengths are taken to be uniform.
    ## Make this the same other theta manipulation functions, and return the tip node theta as 0.  Assume same for input.
    
    my $testPlot = 0;    
    my $numArgs = @_;

    my $numIn = $inThetas->nelem;
    my ($inSegLens,$outSegLens);
    
    if ($numArgs == 2){
        $inSegLens  = ones($numIn-1);
        $outSegLens = (ref(\$arg2) eq "SCALAR") ? ones($arg2-1) : $arg2;
    } elsif ($numArgs == 3){
        $inSegLens  = $arg2;    
        $outSegLens = (ref(\$arg3) eq "SCALAR") ? ones($arg3-1) : $arg3;
    } else {
        die "At least 2 args must be passed.\nStopped";
    }

    # The thetas are angles of a segment relative to the previous segment.  Think of each theta being applied at the START of its segment, and producing a displacement at the segment end.  These accumulate to produce a sequence of cartesian coordinates.  (This is just what we do for the rod in Calc_Qs().)  Then we spline the cartesian coords as a function of arc length, and finish by applying the law of cosines to pull out the resampled thetas.
    
    my ($Xs,$Ys) = IntegrateThetas($inThetas,$inSegLens);
            
    # Normalize arc length:
    my $inCumLens   = cumusumover(zeros(1)->glue(0,$inSegLens));
    $inCumLens  /= $inCumLens(-1);
    
    my $outCumLens  = cumusumover(zeros(1)->glue(0,$outSegLens));
    $outCumLens /= $outCumLens(-1);

    my $xSpline = SplineNew($inCumLens,$Xs);
    my $ySpline = SplineNew($inCumLens,$Ys);

    my $XXs = SplineEvaluate($xSpline,$outCumLens);
    my $YYs = SplineEvaluate($ySpline,$outCumLens);
    
# Compare:
#Plot($Xs,$Ys,"Original",$XXs,$YYs,"Splined","ROD_TEST_PLOT");
    
    my $dXs = $XXs(1:-1)-$XXs(0:-2);
    my $dYs = $YYs(1:-1)-$YYs(0:-2);

    my $tSegLens    = sqrt($dXs**2+$dYs**2);
        
    # Prepend a unit length vertical vector:
    $dXs = zeros(1)->glue(0,$dXs);
    $dYs = ones(1)->glue(0,$dYs);
    $tSegLens = ones(1)->glue(0,$tSegLens);
            

    #if (!$testPlot){warn "WORRY ABOUT ME!\n"}
    my $nums    = $dXs(1:-1)*$dXs(0:-2)+$dYs(1:-1)*$dYs(0:-2);
    my $denoms  = $tSegLens(1:-1)*$tSegLens(0:-2);
    my $quots   = $nums/$denoms;
#pq($nums,$denoms,$quots);

    my $outThetas = acos($quots);    
    $outThetas = $outThetas->glue(0,zeros(1));

#pq($outThetas,$outSegLens);
    
    if ($testPlot){ # Call again with the new thetas and seg lens:
    
        print "\nCALLING TEST PLOTS IN ResampleThetas\n\n";

        $outSegLens = $tSegLens(1:-1)->sever; 
        my ($testXs,$testYs) = IntegrateThetas($outThetas,$outSegLens);
                
        Plot($Xs,$Ys,"Original",$testXs,$testYs,"Fitted","ROD_TEST_PLOT");
    }
        
    return $outThetas;
 }


sub OffsetsToThetasAndSegs {
    my ($dXs,$dYs) = @_;
    
    ## This function is meant to be applied to rod offsets located on an image, with the first offset pair at the true rod butt, the second at the start of the action, and the last at the rod tip.    
    ## On return, drops the rod handle segment, and appends our conventional 0 tip theta.
    
    $dXs = $dXs(1:-1)->sever;
    $dYs = $dYs(1:-1)->sever;
    
    my $outSegLens = sqrt($dXs**2+$dYs**2);
        # The first coordinate pair is supposed to be (0,0).

    my $outThetas =
        acos((($dXs(1:-1)*$dXs(0:-2))+($dYs(1:-1)*$dYs(0:-2)))/
                ($outSegLens(1:-1)*$outSegLens(0:-2)) );
    
    return ($outThetas->glue(0,zeros(1)),$outSegLens(1:-1));
}


sub RodSegWeights { my $verbose = 0?$verbose:0;
    my ($segLens,$nodeDiams,$rodDensity,$fiberGradient,$maxWallThickness) = @_;
    
    ## Figure the  weights and their relative locations in the segments.

    if ($verbose>=4){print "Calculating rod seg weights ---\n"}

    my ($effectiveULVolumes,$effectiveULMoments) = GradedUnitLengthSegments($nodeDiams,$fiberGradient,$maxWallThickness);
    if ($verbose>=4){
        my $rodSegCGs   = $effectiveULMoments/$effectiveULVolumes;
        pq($rodSegCGs);
    }
    
    my $segWeights   = $effectiveULVolumes * $segLens * $rodDensity;
    my $segMoments   = $effectiveULMoments * $segLens * $rodDensity;
    # Note: the last two factors in the moments account for the weight scaling.  A true moment would need an additional $segLens factor.  We are dealing  in RELATIVE moments.  Dividing these by the weights give RELATIVE cgs, that is, the fractional positions of the cgs in the segments.  Those are what we use in the actual calculation.  Perhaps I should always call these $segRelMoments.
    
    if ($verbose>=4){pq($segWeights,$segMoments)}
    return ($segWeights,$segMoments);
}


sub RodSegExtraWeights { my $verbose = 0?$verbose:0;
    my ($segLens,$nodeDiams,$varnishAndGuidesMultiplier,
            $flyLineNomWeight,$handleLen,$numSections) = @_;
    
    ## Figure the extra weights and their relative locations in the segments.
    
    my $nargs = @_;
    if ($verbose>=4){print "Calculating rod extra weights ---\n"}

    #pq($nodeDiams);
    
    # Accumulate, for each segment, over weight sources:
    my $cumsSegWts      = zeros($segLens);
    my $cumSegMoments   = zeros($segLens);
    
    # Varnish and guides approximation. Just a multiple of the surface area.  I apply the hex circumference factor 2*sqrt(3)*D here:
    my $rodVandGWts = 2*sqrt(3) * 0.5*($nodeDiams(1:-1)+$nodeDiams(0:-2))
                        * $segLens * $varnishAndGuidesMultiplier;
    
    if ($verbose>=4){pq $rodVandGWts}
    $cumsSegWts     += $rodVandGWts;
    $cumSegMoments  += 0.5 * $rodVandGWts;     # The cg of the added weight is at the section midpoint.

    
    # Line running through guides:
    my $rodLineWts = $segLens * $flyLineNomWeight;
    if ($verbose>=4){pq $rodLineWts}
    
    $cumsSegWts     += $rodLineWts;
    $cumSegMoments  += 0.5 * $rodLineWts;     # The cg of the added weight is at the section midpoint.
   
    
    # Ferrules (if requested).  Put all their weight in the segment that contains them:
    if (defined($handleLen)){
    
        my ($ferruleNodesBelow,$ferruleFractsBelow) =
            FerruleLocs($segLens,$handleLen,$numSections);
    
        my ($ferruleWts,$ferruleMoments) =
            FerruleWeights($ferruleNodesBelow,$ferruleFractsBelow,$nodeDiams);
        if ($verbose>=4){pq($ferruleWts,$ferruleMoments)}

        $cumsSegWts     += $ferruleWts;
        $cumSegMoments  += $ferruleMoments;
        # The cg of the added weight where it actually is in segment.
    }

    if ($verbose>=4){pq($cumsSegWts,$cumSegMoments)}
    return ($cumsSegWts,$cumSegMoments);
}


sub FerruleLocs { my $verbose = 0?$verbose:0;
	my ($segLens,$handleLen,$numSections) = @_;
    
    ## Locs are relative to rod zero node, not the true rod butt.

    my $numFerrules = $numSections-1;

    my $ferruleNodesBelow       = zeros($numFerrules);
    my $ferruleFractsBelow      = zeros($numFerrules);
    
    if ($numFerrules >= 1) {
    
        my $nodeLocs = cumusumover(zeros(1)->glue(0,$segLens));
        
        my $rodLen = $handleLen + sclr($nodeLocs(-1));
        my $sectionLen = $rodLen/$numSections;
        my $ferruleLocs    = (sequence($numFerrules)+1)*$sectionLen;
        $ferruleLocs -= $handleLen;
#pq($ferruleLocs);
       
        my $iNode = 0;
        my $tNodeLoc = $nodeLocs($iNode);
        for (my $iF=0;$iF<$numFerrules;$iF++) {

            my $tFerruleLoc = $ferruleLocs($iF);
            if ($tFerruleLoc <= 0){die "Detected ferrule in rod handle.Stopped"}
        
            while ($tNodeLoc < $tFerruleLoc){
                $iNode += 1;
                $tNodeLoc = $nodeLocs($iNode);
            }
            
            $ferruleNodesBelow($iF)  .= $iNode-1;
            $ferruleFractsBelow($iF) .= ($tFerruleLoc-$nodeLocs($iNode-1))/$segLens($iNode-1);
            
        }
    }    

	if ($verbose>=4){pq($ferruleNodesBelow,$ferruleFractsBelow)}
    return ($ferruleNodesBelow,$ferruleFractsBelow);
}
    

sub FerruleWeights { my $verbose = 0?$verbose:0;
    my ($ferruleNodesBelow,$ferruleFractsBelow,$rodNodeDiams) = @_;
    
    ## Expects all diams, including handle top and tip, returns weights at those nodes.
    
    my $nSegs = $rodNodeDiams->nelem - 1;
    my $ferruleWts      = zeros($nSegs);
    my $ferruleMoments  = zeros($nSegs);
    #    pq($rodNodeDiams,$ferruleWts);
    
    my $numFerrules = $ferruleNodesBelow->nelem;
    for (my $iF=0;$iF<$numFerrules;$iF++) {
        
        my $tFractBelow = $ferruleFractsBelow($iF);
        my $tFractAbove = 1-$tFractBelow;
        my $tNode       = $ferruleNodesBelow($iF);
        
        my $fDiam =
        sclr($tFractBelow*$rodNodeDiams($tNode)+$tFractAbove*$rodNodeDiams($tNode+1));
        
        # Look up diam in table:
        my $sixtyfourths = POSIX::ceil($fDiam*64);
        my $fWt = $ferruleWtsSuperZ[$sixtyfourths];
        if (!$fWt){die "Ferrule diameter not found in table.Stopped"}
        
        if ($verbose>=4){print "fDiam=$fDiam,fWt=$fWt\n";}
        
        $ferruleWts($tNode)         += $fWt;
        $ferruleMoments($tNode)     += $tFractBelow*$fWt;    # Sic
        
    }
    
    if ($verbose>=4){pq($ferruleWts,$ferruleMoments)}
    return ($ferruleWts,$ferruleMoments);
}


sub RodKs { my $verbose = 0?$verbose:0;
    my ($segLens,$effectiveSect2ndMoments,$rodElasticModulus,$ferruleKsMult,$handleLen,$numSections) = @_;
    
    ## Expects all diams, including handle top and tip, returns Ks at those nodes.  If ferruleKsMult is non-zero, stiffens the adjacent nodes proportionally to their distances from the ferrule location.
    
    ###     From http://en.wikipedia.org/wiki/Euler-Bernoulli_beam_equation
    ###     Energy is 0.5*EI(d2W/dx2)**2, where
    ###     I = hex2ndAreaMoment*diam**4.
    
    ## NOTE:  Each node provides an elastic force proportional to theta.  The illuminating model is not a series of point-like hinge springs, but rather a local bent rod of uniform section and length equal to the segment length L.  If the rod axis is deformed into a uniform curve whose angle at the center of curvature is theta, L = R*theta, where R is the radius of curvature.  A fiber offset outward from the axis by the amount delta is stretched from its original length L to length (R+delta)*theta, so the change in length is (R+delta)*theta - L = (R+delta)*theta - R*theta = delta*theta, and the proportional change (strain) is delta*theta/L.  By Hook's Law and the definition of the elastic modulus E (= force per square inch needed to make dL equal L, that is, to double the length), we get force equal to (delta/L)*E*dA*theta, where dA is the cross-sectional area of a small bundle of fibers at delta from the axis.  Doing the integration over our hexagonal rod section, (including the compressive elastic forces on fiber bundles offset inward from the axis), we end up with a total elastic force tending to straighten the rod segment whose magnitude is (E*hex2ndAreaMoment*diam**4/L)*theta.  As a check, notice that since E (as we use it here) has units of ounces per square inch, and the hex form constant and theta are dimensionless, the product has units ounce-inches, which is what we require for a torque.  Of course, diam and L must be expressed in the SAME units, here inches.
    
    ## In more detail (and perhaps more correctly):  The work done by a force on a fiber is the cartesian force at that cartesian stretch times a cartesian displacement.  So want to figure the stretch energy in cartesian.  The cartesian force = E*stretch/L, and the WORK = (E/(2*L)*stretch**2.  So in terms of theta, WORK = (E/(2*L)*(delta*theta)**2 = (E*delta**2/(2*L)*theta**2.  So the GENERALIZED force due to theta is the theta derivative of this -- GenForce(theta) =  (E/L)*(delta**2)*theta. It is the delta**2 that integrates over the area to give the SECOND hex MOMENT, our in our case, the second power fiber count moment.  According to Hamilton, it is the generalized force that gives the time change of the associated generalized momentum.  Therefore, it is what we use in our pDots calculation.
    
    my $effective2ndMomentsNoTip = $effectiveSect2ndMoments(0:-2);
    #    pq($rodElasticModulus,$pf2ndMomentsNoTip,$segLens);
    
    my $rodKsNoTip = $rodElasticModulus*$effective2ndMomentsNoTip/$segLens;
    if ($verbose>=4){print "rodKsNoTip(before ferrules)=$rodKsNoTip\n";}

    if ($ferruleKsMult){
        # Stiffen nodes adjacent to the ferrules:
        
        my ($ferruleNodesBelow,$ferruleFractsBelow) =
                FerruleLocs($segLens,$handleLen,$numSections);
        
        my $tKs = $rodKsNoTip->glue(0,zeros(1));
        my $ttKs = zeros($tKs);
        my $tMult = $ferruleKsMult;
        for (my $iF=0;$iF<$ferruleNodesBelow->nelem;$iF++){
            my $tNode   = $ferruleNodesBelow($iF);
            my $tFract  = $ferruleFractsBelow($iF);
            $ttKs($tNode) +=
            $tKs($tNode)*(1-$tFract)*$tMult;    # Sic
            $ttKs($tNode+1) +=
            $tKs($tNode+1)*$tFract*$tMult;      # Sic
        }
        $rodKsNoTip += $ttKs(0:-2);
        #pq($numSections,$ferruleNodesBelow,$ferruleFractsBelow);
    }
    if ($verbose>=4){print "rodKsNoTip(after ferrules)=$rodKsNoTip\n";}

    return $rodKsNoTip;
}


sub ShortDateTime {
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;

    $year   = sprintf("%02d", $year % 100);
    $mon    = sprintf("%02d", $mon+1);  # Sic
    $mday   = sprintf("%02d", $mday);
    my $dateNum = $year . $mon . $mday;
    
    $hour   = sprintf("%02d", $hour);
    $min    = sprintf("%02d", $min);
    $sec    = sprintf("%02d", $sec);
    my $timeNum = $hour . $min . $sec;
    
    return ($dateNum,$timeNum);                                                
}



# Required package return value:
1;

__END__

=head1 NAME

RCommon - Common globals as well as specific physical, mathematical, and string handling utilities used by the elements of the RHex project.  Of special note, defines and exports the constant DEBUG which when set enables additional levels of verbosity and some extra debugging features, including automatic verbosity boosting.

=head1 SYNOPSIS

use RCommon;

=head1 ABOUT DEBUG

use constant DEBUG => 1;    # 0, or non-zero for debugging behavior, including higher level verbosity.  In particular the string "DEfunc_GSL" prints stepper outputs engendered by the stepper function DE() and "DEjac_GSL" prints jacobian outputs from the same source.  Actually, any true value for DEBUG except "DEjac_GSL" defaults to DEfunc_GSL".


=head1 EXPORT

DEBUG $launchDir $verbose $debugVerbose $vs $rSwingOutFileTag $rCastOutFileTag $inf $neginf $nan $pi $massFactor $massDensityAir $airBlubsPerIn3 $kinematicViscosityAir $kinematicViscosityWater $waterBlubsPerIn3 $waterOzPerIn3 $massDensityWater $grPerOz $hexAreaFactor $hex2ndAreaMoment GradedSections GradedUnitLengthSegments StationDataToDiams DiamsToStationData DefaultDiams DefaultThetas IntegrateThetas ResampleThetas OffsetsToThetasAndSegs NodeCenteredSegs RodSegWeights RodSegExtraWeights FerruleLocs FerruleWeights RodKs GetValueFromDataString GetWordFromDataString GetArrayFromDataString GetQuotedStringFromDataString SetDataStringFromMat GetMatFromDataString Str2Vect BoxcarVect LowerTri ResampleVectLin ResampleVect SplineNew SplineEvaluate SmoothChar_Setup SmoothChar SmoothOnset SecantOffsets SkewSequence RelocateOnArc ReplaceNonfiniteValues exp10 MinMerge MaxMerge PrintSeparator StripLeadingUnderscores HashCopy1 HashCopy2 ShortDateTime

=head1 AUTHOR

Rich Miller, E<lt>rich@ski.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2019 by Rich Miller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.28.1 or,
at your option, any later version of Perl 5 you may have available.


=cut


