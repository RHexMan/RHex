# RCommonPlot3D.pl

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

# Combined run plotting and saving for RHexCast3D, RSHexink3D, and RHexReplot3D.

package RCommonPlot3D;

use warnings;
use strict;

our $VERSION='0.01';

use POSIX ();
#require POSIX;
    # Require rather than use avoids the redefine warning when loading PDL.  But then I must always explicitly name the POSIX functions. See http://search.cpan.org/~nwclark/perl-5.8.5/ext/POSIX/POSIX.pod.  Implements a huge number of unixy (open ...) and mathy (floor ...) things.

use Exporter 'import';
#our @EXPORT = qw( spectrum2 RCommonPlot3D RCommonSave3D);
our @EXPORT = qw( $gnuplot RCommonPlot3D RCommonSave3D);

use Carp;

use Switch;

use PDL;
use PDL::AutoLoader;    # MATLAB-like autoloader.
use PDL::NiceSlice;
use PDL::Options;       # For iparse. http://pdl.perl.org/index.php?docs=Options&title=PDL::Options

use Chart::Gnuplot;

use RUtils::Print;
use RCommon;

our $gnuplot = '';


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
	
	if ($numRodNodes == 1){	# No rod, so I want the zScale mechanism.
    	#$zMin   = $cz-$range/(2*$zScale);
    	#$zMax   = $cz+$range/(2*$zScale);
    	$zMin   = $zMin/$zScale;
    	$zMax   = ($zMax+1)/$zScale;
	} else { # Noop, use the min and max as they are.
		$zMin -= 1;
	}
    
    # In setting the vertical range, don't let it go below the stream bottom:
    #if ($zMin<$plotBottom){$zMin = $plotBottom}
    
    if (DEBUG and $verbose>=5){pq($range,$xMin,$xMax,$yMin,$yMax,$zMin,$zMax)}
    
    my $lastTime = $Ts(-1)->sclr;
    my $errStr  = ($errMsg) ? "\n$errMsg" : "";
    
    my $titleText = $titleStr." -- latestT=$lastTime -- ".$paramsStr.$errStr;
    $titleText =~ s/\t/ /g;
    $titleText =~ s/\n/\\n/g;
    # And this substitution worked!
	
	my $xyplaneStr	= ($numRodNodes == 1) ? "at $plotBottom" : "at $zMin";
	#my $viewStr		= ($numRodNodes == 1) ? ",,,1.0" : ",,1.0,0.2";
	my $zScaleStr	= 1/$zScale;
	my $viewStr		= ($numRodNodes == 1) ? ",,,1.0" : ",,1.0,$zScaleStr";
	
    my $chart = Chart::Gnuplot->new(
    title  => "$titleText",
    xlabel => "X (ft)",
    ylabel => "Y (ft)",
    zlabel => "Z (ft)",
	view   => "$viewStr",
    #view    => ",,,1.0",    # This makes no sense to me, but gives the equal lengths that I want.
    #view    => ",,1.0,0.2",    # This is supposed to scale both (x,y) and z the same.  But     view    => ",,1.0,0.4",    # This is supposed to scale both (x,y) and z the same.
	# But the 1.0's are supposed to be the default. 0.4 in z amplifies.
	#view    => ",,,$compensatedZScale",
    #view    => ",,,$zScale",
    #view    => "equal xyz",
    #xyplane => "at $zMin",
    #xyplane => "at $plotBottom",
	xyplane => "$xyplaneStr"
    );
    
    # Chart::Gnuplot lets us try to find our own copy of gnuplot.  I do this to streamline installation on other macs, where I put a copy in the execution directory:
    if ($opts->{gnuplot}){$chart->gnuplot($opts->{gnuplot})}
    
    switch ($output) {
        case "window" {
            #$chart->terminal("x11 persist size 900,900");
            $chart->terminal("x11 size 900,900");
			# Better not to persist.  The windows stay up as long as the control panel is there, and then go away when you hit the quit button.
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
	
	$chart->xrange(["-2*$range<*:*<2*$range"]);
	$chart->yrange(["-2*$range<*:*<2*$range"]);
	

if (0){
    $chart->xrange(["$xMin", "$xMax"]);
    $chart->yrange(["$yMin", "$yMax"]);
	#$chart->zrange(["$plotBottom", "$zMax"]);
    if ($numRodNodes == 1){$chart->zrange(["$plotBottom", "$zMax"])}
	else {$chart->zrange(["$zMin", "$zMax"])}
	
    #$chart->zrange(["$zMin", "$zMax"]);
}
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

__END__

=head1 NAME

RCommonPlot3D - Combined run plotting and saving for RHexCast3D, RSHexink3D, and RHexReplot3D.

=head1 SYNOPSIS

use RCommon;

=head1 DESCRIPTION

Calls gnuplot in an X11 environment to create rotatable 3D plots showing rod and/or line traces at user defined uniform time intervals during a simulation.  The saving function creates an .eps file capturing a static image of the traces and/or a .txt file that captures the trace and parameter data.  The text files can later be used to simply look at the numbers, but they also form the input to RHexReplot3D, which will redraw the plots in rotatable form.

Can plot using a system gnuplot if it is available, or the local version bundled with the RHex project.

=head1 EXPORT

$gnuplot RCommonPlot3D RCommonSave3D

=head1 GNUPLOT VERSION

The show version command lists the version of gnuplot being run, its last modification date, the copyright holders, and email addresses for the FAQ, the gnuplot-info mailing list, and reporting bugs–in short, the information listed on the screen when the program is invoked interactively.

=over

Syntax:
     show version {long}
	 
=back

When the long option is given, it also lists the operating system, the compilation options used when gnuplot was installed, the location of the help file, and (again) the useful email addresses.


=head1 GNUPLOT KEY BINDINGS

Plots drawn by gnuplot in X11 windows can be manipulated by the user in many ways.  The most obvious and most useful is rotation by dragging with the mouse.  Zooming in and out is also essential for looking at details.  Here is a complete list of the key and mouse bindings.  All the letter options need to have the command key held while pressing the letter key.  The most important of these is <cmd-u>, which undoes all zooming and scrolling, resetting to the original configuration.  On macs running newer systems, the important <control-wheel-up> and <control-wheel-down> combinations are by default pre-empted by the Accessibility controler.  You can simply go to SystemPreferences/Accessibility and uncheck "Use scroll gesture ... ", or leave it checked but change the modifier key to "command":

Holding down the wheel button while dragging right and left zooms the whole picture without changing the relative scaling, dragging it up or down does something else which I don't yet understand

=over

gnuplot> show bind

 2x<B1>             print coordinates to clipboard using `clipboardformat`
                    (see keys '3', '4')
 <B2>               annotate the graph using `mouseformat` (see keys '1', '2')
                    or draw labels if `set mouse labels is on`
 <Ctrl-B2>          remove label close to pointer if `set mouse labels` is on
 <B3>               mark zoom region (only for 2d-plots and maps).
 <B1-Motion>        change view (rotation). Use <ctrl> to rotate the axes only.
 <B2-Motion>        change view (scaling). Use <ctrl> to scale the axes only.
 <Shift-B2-Motion>  vertical motion -- change xyplane
 <wheel-up>         scroll up (in +Y direction).
 <wheel-down>       scroll down.
 <shift-wheel-up>   scroll left (in -X direction).
 <shift-wheel-down>  scroll right.
 <control-wheel-up>  zoom in toward the center of the plot.
 <control-wheel-down>   zoom out.
 <shift-control-wheel-up>  zoom in only the X axis.
 <shift-control-wheel-down>  zoom out only the X axis.

Space          raise gnuplot console window
 q            * close this plot window

 a              `builtin-autoscale` (set autoscale keepfix; replot)
 b              `builtin-toggle-border`
 e              `builtin-replot`
 g              `builtin-toggle-grid`
 h              `builtin-help`
 l              `builtin-toggle-log` y logscale for plots, z and cb for splots
 L              `builtin-nearest-log` toggle logscale of axis nearest cursor
 m              `builtin-toggle-mouse`
 r              `builtin-toggle-ruler`
 1              `builtin-previous-mouse-format`
 2              `builtin-next-mouse-format`
 3              `builtin-decrement-clipboardmode`
 4              `builtin-increment-clipboardmode`
 5              `builtin-toggle-polardistance`
 6              `builtin-toggle-verbose`
 7              `builtin-toggle-ratio`
 n              `builtin-zoom-next` go to next zoom in the zoom stack
 p              `builtin-zoom-previous` go to previous zoom in the zoom stack
 u              `builtin-unzoom`
 Right          `builtin-rotate-right` only for splots; <shift> increases amount
 Up             `builtin-rotate-up` only for splots; <shift> increases amount
 Left           `builtin-rotate-left` only for splots; <shift> increases amount
 Down           `builtin-rotate-down` only for splots; <shift> increases amount
 Escape         `builtin-cancel-zoom` cancel zoom region
 
=back

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



