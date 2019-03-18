package RCommonPlot3D;

# Combined run plotting and saving for RHexCast3D and RSink3D.

use warnings;
use strict;
use POSIX ();
#require POSIX;
    # Require rather than use avoids the redefine warning when loading PDL.  But then I must always explicitly name the POSIX functions. See http://search.cpan.org/~nwclark/perl-5.8.5/ext/POSIX/POSIX.pod.  Implements a huge number of unixy (open ...) and mathy (floor ...) things.

#use Carp;

use Exporter 'import';
our @EXPORT = qw( spectrum2 RCommonPlot3D RCommonSave3D);

use Switch;

use PDL;
use PDL::AutoLoader;    # MATLAB-like autoloader.
use PDL::NiceSlice;
use PDL::Options;       # For iparse. http://pdl.perl.org/index.php?docs=Options&title=PDL::Options

use Chart::Gnuplot;

use RPrint;
use RCommon;


sub spectrum2 {
    my ($rgb0,$rgb1,$fract)= @_;
    # 3-component flat pdls, each in range 0:255;
    
    my $colors = $rgb0->glue(1,$rgb1);
    my $fracts = zeros(2);
    $fracts(0) .= 1-$fract;
    $fracts(1) .= $fract;
    my $rgb = ($fracts x $colors)->flat->floor;
    my $val = sclr($rgb(0)*65536 + $rgb(1)*256 + $rgb(2));
    return sprintf("#%x",$val);
}

sub RCommonPlot3D {
    my($output,$plotFile,$titleStr,$paramsStr,
    $Ts,$Xs,$Ys,$Zs,$XLineTips,$YLineTips,$ZLineTips,$XLeaderTips,$YLeaderTips,$ZLeaderTips,$numRodNodes,$plotBottom,$errMsg,$verbose,$opts) = @_;
    
    $opts = {iparse( {gnuplot=>'',ZScale=>1,RodStroke=>1,RodTip=>6,RodHandle=>1,RodTicks=>1,
        ShowLine=>1,LineStroke=>1,LineTicks=>1,LineTip=>7,LeaderTip=>13,Fly=>5},
        ifhref($opts))};
    my ($zScale,$rodStroke,$rodTip,$rodHandle,$rodTicks,
    $showLine,$lineStroke,$lineTicks,$lineTip,$leaderTip,$fly) =
    map {$opts->{$_}} qw/ ZScale RodStroke RodTip RodHandle RodTicks ShowLine LineStroke LineTicks LineTip LeaderTip Fly/;
    
    #print "opts=($rodStroke,$rodTip,$rodHandle,$rodTicks,$showLine,$lineStroke,$lineTip,$lineTicks)\n";
    
    ## See RPlot3D or Chart/Gnuplot/Util.pm for the conversion of named linetype, pointtype, etc to numerical equivalents.
    
    # To keep the slice indices working correctly, force $numRodNodes to be at least one:
    if ($numRodNodes < 1){$numRodNodes = 1}
    
    # Isolate the local data, work in feet:
    $Ts = $Ts->copy;
    $Xs = ($Xs->copy)/12;
    $Ys = ($Ys->copy)/12;
    $Zs = ($Zs->copy)/12;
    
    #pq($Xs,$Ys,$Zs);
    
    $XLineTips      = ($XLineTips->copy)/12;
    $YLineTips      = ($YLineTips->copy)/12;
    $ZLineTips      = ($ZLineTips->copy)/12;
    
    $XLeaderTips    = ($XLeaderTips->copy)/12;
    $YLeaderTips    = ($YLeaderTips->copy)/12;
    $ZLeaderTips    = ($ZLeaderTips->copy)/12;
    
    $plotBottom /= 12;
    
    #pq($XLineTips,$YLineTips,$ZLineTips,$XLeaderTips,$YLeaderTips,$ZLeaderTips);
    
    my ($numNodes,$numTraces) = $Xs->dims;
    if (!$numTraces){$numTraces = 1}
    
    my $numLineNodes = $numNodes-$numRodNodes;
    if (!$showLine){
        $Xs = $Xs(0:$numRodNodes-1);
        $Ys = $Ys(0:$numRodNodes-1);
        $Zs = $Zs(0:$numRodNodes-1);
    }
    
    ## See Chart/Gnuplot/Util.pm for the conversion of named linetype, pointtype, etc to numerical equivalents.
    my $rgb0 = pdl('0,255,0');  # Start on green,
    my $rgb1 = pdl('255,0,0');  # end on red.
    
    my ($xMin,$yMin,$zMin) = map {$inf} (0..2);
    my ($xMax,$yMax,$zMax) = map {$neginf} (0..2);
    
    my @dataSets = ();
    my $iDataSet = 0;
    
    for (my $ii=0;$ii<$numTraces;$ii++) {
        
        my $fract = $ii/$numTraces;
        my $color = spectrum2($rgb0,$rgb1,$fract);
        my $jjBnd = ($numLineNodes>0 and $showLine) ? 7 : 3;
        
        for (my $jj=0;$jj<$jjBnd;$jj++) {
            
            my $linetype;
            my $pointtype;
            my (@aPlotXs,@aPlotYs,@aPlotZs);
            
            if ($jj==0){    # rod
                #pq($jj);
                $linetype   = $rodStroke;
                $pointtype  = ($rodTicks) ? 1 : 0;
                @aPlotXs = $Xs(0:$numRodNodes-1,$ii)->list;
                @aPlotYs = $Ys(0:$numRodNodes-1,$ii)->list;
                @aPlotZs = $Zs(0:$numRodNodes-1,$ii)->list;
            } elsif ($jj==1) {    # Mark the rod tip:
                #pq($jj);
                $linetype   = 0;
                $pointtype  = $rodTip;
                @aPlotXs = $Xs($numRodNodes-1,$ii)->list;
                @aPlotYs = $Ys($numRodNodes-1,$ii)->list;
                @aPlotZs = $Zs($numRodNodes-1,$ii)->list;
            } elsif ($jj==2) {    # Mark the rod handle:
                #pq($jj);
                $linetype   = 0;
                $pointtype  = $rodHandle;
                my $iEnd = ($numRodNodes>=2) ? 1 : 0;
                @aPlotXs = $Xs(0:$iEnd,$ii)->list;
                @aPlotYs = $Ys(0:$iEnd,$ii)->list;
                @aPlotZs = $Zs(0:$iEnd,$ii)->list;
            } elsif ($jj==3) { # line
                #pq($jj);
                $linetype   = $lineStroke;
                $pointtype  = ($rodTicks) ? 1 : 0;
                @aPlotXs = $Xs($numRodNodes-1:-1,$ii)->list;
                @aPlotYs = $Ys($numRodNodes-1:-1,$ii)->list;
                @aPlotZs = $Zs($numRodNodes-1:-1,$ii)->list;
                # Sic, line starts at rod tip.
            } elsif ($jj==4) {    # Mark the fly:
                #pq($jj);
                $linetype   = $lineStroke;  # long dash
                $pointtype  = $fly;
                #$pointtype  = 7; # solid circle
                @aPlotXs = $Xs(-1,$ii)->list;
                @aPlotYs = $Ys(-1,$ii)->list;
                @aPlotZs = $Zs(-1,$ii)->list;
                #pq(\@aPlotXs,\@aPlotYs);
            } elsif ($jj==5) {    # Mark the line-leader junction:
                #pq($jj);
                $linetype   = $lineStroke;  # long dash
                $pointtype  = $lineTip; # dot-triangle
                #$pointtype  = 9; # solid triangle
                @aPlotXs = $XLineTips(0,$ii)->list;
                @aPlotYs = $YLineTips(0,$ii)->list;
                @aPlotZs = $ZLineTips(0,$ii)->list;
                #pq(\@aPlotXs,\@aPlotYs);
            } elsif ($jj==6) {    # Mark the leader-tippet junction:
                #pq($jj);
                $linetype   = $lineStroke;  # long dash
                $pointtype  = $leaderTip;
                #$pointtype  = 5; # solid square
                @aPlotXs = $XLeaderTips(0,$ii)->list;
                @aPlotYs = $YLeaderTips(0,$ii)->list;
                @aPlotZs = $ZLeaderTips(0,$ii)->list;
            }
            
            $dataSets[$iDataSet++] = Chart::Gnuplot::DataSet->new(
                linetype => "$linetype",
                pointtype => "$pointtype",
                style => "linespoints",
                color => "$color",
                xdata => \@aPlotXs,
                ydata => \@aPlotYs,
                zdata => \@aPlotZs,
            );
            #pq($jj,\@aPlotXs,\@aPlotYs,\@aPlotZs);
            
            # Gather plot bounds data:
            my $xs = pdl(@aPlotXs);
            my $ys = pdl(@aPlotYs);
            my $zs = pdl(@aPlotZs);
            
            $xs = where($xs,$xs->isfinite);
            $ys = where($ys,$ys->isfinite);
            $zs = where($zs,$zs->isfinite);

            #if (all($xs->isfinite)){
            if (!$xs->isempty){
                my $txMin = $xs->min;
                my $txMax = $xs->max;
                if ($txMin < $xMin){$xMin = $txMin}
                if ($txMax > $xMax){$xMax = $txMax}
            }
            if (!$ys->isempty){
                my $tyMin = $ys->min;
                my $tyMax = $ys->max;
                if ($tyMin < $yMin){$yMin = $tyMin}
                if ($tyMax > $yMax){$yMax = $tyMax}
            }
            if (!$zs->isempty){
                my $tzMin = $zs->min;
                my $tzMax = $zs->max;
                if ($tzMin < $zMin){$zMin = $tzMin}
                if ($tzMax > $zMax){$zMax = $tzMax}
            }
        }
    }
    
    # Set the plot bounds:
    my $dx = $xMax-$xMin;
    my $dy = $yMax-$yMin;
    my $dz = $zMax-$zMin;
    
    my $cx = ($xMin+$xMax)/2;
    my $cy = ($yMin+$yMax)/2;
    my $cz = ($zMin+$zMax)/2;
    
    my $range   = ($dy>$dx)?$dy:$dx;
    $range      = ($range>$dz)?$range:$dz;
    
    $xMin   = $cx-$range/2;
    $xMax   = $cx+$range/2;
    $yMin   = $cy-$range/2;
    $yMax   = $cy+$range/2;
    $zMin   = $cz-$range/(2*$zScale);
    $zMax   = $cz+$range/(2*$zScale);
    
    # In setting the vertical range, don't let it go below the stream bottom:
    #if ($zMin<$plotBottom){$zMin = $plotBottom}
    
    if (DEBUG and $verbose>=5){pq($range,$xMin,$xMax,$yMin,$yMax,$zMin,$zMax)}
    
    my $lastTime = $Ts(-1)->sclr;
    my $errStr  = ($errMsg) ? "\n$errMsg" : "";
    
    my $titleText = $titleStr." -- latestT=$lastTime -- ".$paramsStr.$errStr;
    $titleText =~ s/\t/ /g;
    $titleText =~ s/\n/\\n/g;
    # And this substitution worked!
    
    my $chart = Chart::Gnuplot->new(
    title  => "$titleText",
    xlabel => "X (ft)",
    ylabel => "Y (ft)",
    zlabel => "Z (ft)",
    view    => ",,,1.0",    # This makes no sense to me, but gives the equal lengths that I want.
    #view    => ",,,$compensatedZScale",
    #view    => ",,,$zScale",
    #view    => "equal xyz",
    #xyplane => "at $zMin",
    xyplane => "at $plotBottom",
    );
    
    # Chart::Gnuplot lets us try to find our own copy of gnuplot.  I do this to streamline installation on other macs, where I put a copy in the execution directory:
    if ($opts->{gnuplot}){$chart->gnuplot($opts->{gnuplot})}
    
    switch ($output) {
        case "window" {
            $chart->terminal("x11 persist size 900,900");
        }
        case "file" {
            $chart->terminal("postscript enhanced color size 10,7");
            # Default is 10" x 7" (landscape).
            # Terminal defaults to enhanced color if not set, but if it is set, as here to set size, enhanced color needs to be added to the string manually.  Note that the value of terminal needs to be a whitespace separated string with the first item containing a recognized terminal name, here post or postscript.
            # Looking at Gnuplot.pm, new() automatically adds " eps" to the terminal value if output has the eps extension.  This explains the "eps redundant" error.
            my $outfile = $plotFile.'.eps';
            $chart->output("$outfile");
        }
        else {die "Unknown output.\n"}
    }
    
    $chart->xrange(["$xMin", "$xMax"]);
    $chart->yrange(["$yMin", "$yMax"]);
    $chart->zrange(["$plotBottom", "$zMax"]);
    #$chart->zrange(["$zMin", "$zMax"]);
    
    if (DEBUG and $verbose>=5){print Data::Dump::dump($chart), "\n"}
    
    # Plot the datasets on the devices:
    if ($plotFile and $output eq "file"){
        $chart->plot3d(@dataSets);
    } elsif ($output eq "window"){
        my $pid = fork();
        if( $pid == 0 ){
            # Zero is the child's PID,
            $chart->plot3d(@dataSets);  # This never returns.
            exit 0;
        }
        # Non-zero is the parent's.
    }
}

sub RCommonSave3D {
    my($filename,$outFileTag,$titleStr,$paramsStr,
    $Ts,$Xs,$Ys,$Zs,$XLineTips,$YLineTips,$ZLineTips,$XLeaderTips,$YLeaderTips,$ZLeaderTips,$numRodNodes,$plotBottom,$errMsg,
        $finalT,$finalState,$segLens) = @_;
    
    ## Save plot data to a file for future manipulation and plotting. plotTs is a pdl vector and plotXs, plotYs are pdl matrices.  Write the rows as tab separated lines.
    
    
    my ($numNodes,$numTraces) = $Xs->dims;
    if (!$numTraces){$numTraces = 1}
    
    if ($errMsg){
        $paramsStr .= "\n$errMsg";
    }
    #pq $$paramsStr;
    
    my $outStr = "$outFileTag\n\n";
    $outStr .= "ParamsString:\n\'$paramsStr\'\n\n";
    
    $outStr .= "NumRodNodes:\t$numRodNodes\n\n";
    
    #pq($numTraces,$Ts);
    
    $outStr .= SetDataStringFromMat($Ts->reshape($numTraces,1),"PlotTs")."\n";
    $outStr .= SetDataStringFromMat($Xs,"PlotXs")."\n";
    $outStr .= SetDataStringFromMat($Ys,"PlotYs")."\n";
    $outStr .= SetDataStringFromMat($Zs,"PlotZs")."\n";
    
    $outStr .= SetDataStringFromMat($XLineTips,"PlotXLineTips")."\n";
    $outStr .= SetDataStringFromMat($YLineTips,"PlotYLineTips")."\n";
    $outStr .= SetDataStringFromMat($ZLineTips,"PlotZLineTips")."\n";
    
    $outStr .= SetDataStringFromMat($XLeaderTips,"PlotXLeaderTips")."\n";
    $outStr .= SetDataStringFromMat($YLeaderTips,"PlotYLeaderTips")."\n";
    $outStr .= SetDataStringFromMat($ZLeaderTips,"PlotZLeaderTips")."\n";
    
    $outStr .= "PlotBottom:\t$plotBottom\n\n";
    
    
    #    $outStr .= "TimeString:\n\'$dateTimeLong\'\n\n";
    $outStr .= "RunIdentifier: $titleStr\n\n";
    
    $outStr .= "$paramsStr\n\n"; # Removed \'s
    $outStr .= SetDataStringFromMat($finalT,"Time")."\n";
    $outStr .= SetDataStringFromMat($finalState,"State")."\n";
    $outStr .= SetDataStringFromMat($segLens,"SegLengths")."\n";
    
    #pq $outStr;
    
    open OUTFILE,"> $filename".'.txt' or die $!;   # WRITE FROM SCRATCH!
    print OUTFILE $outStr;
    close OUTFILE;
    
    
}

# Required package return value:
1;
