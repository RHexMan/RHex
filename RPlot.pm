#!/usr/bin/perl

#############################################################################
## Name:			RPlot
## Purpose:			Quick plotting functions
## Author:			Rich Miller
## Modified by:
## Created:			2017/10/27
## Modified:		2019/2/18
## RCS-ID:
## Copyright:		(c) 2017 and 2019 Rich Miller
## License:			This program is free software; you can redistribute it and/or
##					modify it under the same terms as Perl itself
#############################################################################

# syntax:  use RPlot;

package RPlot;

# Utility plotting routines.

my $verbose = 0;

use warnings;
use strict;
use POSIX ();
#require POSIX;
    # Require rather than use avoids the redefine warning when loading PDL.  But then I must always explicitly name the POSIX functions. See http://search.cpan.org/~nwclark/perl-5.8.5/ext/POSIX/POSIX.pod.  Implements a huge number of unixy (open ...) and mathy (floor ...) things.

use Carp;

use Exporter 'import';
our @EXPORT = qw( Plot PlotMat Plot3D);

use PDL;
use PDL::AutoLoader;    # MATLAB-like autoloader.
use PDL::NiceSlice;

use Chart::Gnuplot;

use RPrint;

my $inf    = 9**9**9;
my $neginf = -9**9**9;
my $nan    = -sin(9**9**9);

## See extensive comments at the end of this file.


sub Plot {

    ## A quick test plotting function.  Initial args must be in  groups of three, matching pdl pairs followed by a label string.  After the last group, one or two string args may be passed.  The first will be taken to be the plot title, and the second the name of a file to which the plot will be written.  If the filename starts with the string "ONLY", plotting to the terminal is suppressed.

    my $nargs = @_;
    if ($nargs < 1){croak "Plot:  At least 1 pdl arg must be passed.\n"}
    if ($nargs == 1){$nargs = unshift(@_,sequence($_[0]->nelem))}
    
    my ($plotTitle,$plotFile) = ('','');
    my $lastArg = $_[$nargs-1];
    if (ref(\$lastArg) eq 'SCALAR'){
        if ($nargs%3 == 2){
            $plotFile = $lastArg;
            $plotTitle = $_[$nargs-2];
            pop @_; pop @_;
        }elsif ($nargs%3 == 1){
            $plotTitle = $lastArg;
            pop @_;
        }
    }else{  # last arg is not a scalar
        if ($nargs%3 != 2){croak "Plot: pdls must come in pairs.\n"}
        else {push(@_,'')}
    }
    my $numTraces = @_;
    $numTraces /= 3;
    
    if ($verbose>=1){print "In Plot($plotFile)\n"}

    my $useTerminal = (substr($plotFile,0,4) ne "ONLY");
    if (!$useTerminal){$plotFile = substr($plotFile,4)}
    
    if ($verbose>=3){print "useTerminal=$useTerminal\n"}
    
    
    # Create chart object and specify its properties:
    my $chart = Chart::Gnuplot->new(
    xlabel => "Independent Variable(s)",
    ylabel => "Dependent Variable(s)",
        title  => "$plotTitle",
    );
    
    if ($useTerminal) {
            $chart->terminal("x11 persist size 1000,800");
            # 800,618 is 8.5x11 in landscape orientation.
    } else {
            $chart->terminal("postscript enhanced color size 10,7");
            # Default is 10" x 7" (landscape).
            # Terminal defaults to enhanced color if not set, but if it is set, as here to set size, enhanced color needs to be added to the string manually.  Note that the value of terminal needs to be a whitespace separated string with the first item containing a recognized terminal name, here post or postscript.
            # Looking at Gnuplot.pm, new() automatically adds " eps" to the terminal value if output has the eps extension.  This explains the "eps redundant" error.
            my $outfile = $plotFile.'.eps';
            $chart->output("$outfile");
     }

    
    my @dataSets = ();
    for (my $ii=0;$ii<$numTraces;$ii++) {
        my ($xArg,$yArg,$labelArg) = (shift,shift,shift);

        if ($verbose>=3){pq($ii,$xArg,$yArg,$labelArg)}

        my @aXs = $xArg->list;
        my @aYs = $yArg->list;
        
        $dataSets[$ii] = Chart::Gnuplot::DataSet->new(
            xdata => \@aXs,
            ydata => \@aYs,
            title => $labelArg,
            style => "linespoints",
        ); 
    }
    
    if ($verbose>=5) {
        print Data::Dump::dump($chart), "\n";
    }

    # Plot the datasets on the devices:
    if (!$useTerminal){
        $chart->plot2d(@dataSets);
    } else {
        my $pid = fork();
        if( $pid == 0 ){
            # Zero is the child's PID,
            $chart->plot2d(@dataSets);  # This never returns.
            exit 0;
        }
        # Non-zero is the parent's.
    }
}



sub PlotMat {
    my ($inMat,$vOffset,$plotTitle,$plotFile) = @_;
    
    ## A quick test plotting function.  Plots the later columns of the matrix against the first column with the desired vertical offset between traces.  If the filename starts with the string "ONLY", plotting to the terminal is suppressed.
    
    my $numArgs = @_;
    if ($numArgs<1){croak "At least one argument must be passed, and it must be a 2-d pdl.\n"}
    if ($numArgs<2){$vOffset = 0}
    if ($numArgs<3){$plotTitle = ""}
    if ($numArgs<4){$plotFile = ""}
    
    #    if (!defined($plotFile)){$plotFile = ''}
    my $useTerminal = (substr($plotFile,0,4) ne "ONLY");
    if (!$useTerminal){$plotFile = substr($plotFile,4)}
    
    if ($verbose>=1){print "numArgs=$numArgs\n"}
    if ($verbose>=1){print "In PlotMat:\n"}
    
    # Create chart object and specify its properties:
    my $chart = Chart::Gnuplot->new(
    xlabel => "Independent Variable",
    ylabel => "Dependent Variable(s)",
    title  => "$plotTitle",
    );
    
    if ($useTerminal) {
        $chart->terminal("x11 persist size 1000,800");
        # 800,618 is 8.5x11 in landscape orientation.
    } else {
        $chart->terminal("postscript enhanced color size 10,7");
        # Default is 10" x 7" (landscape).
        # Terminal defaults to enhanced color if not set, but if it is set, as here to set size, enhanced color needs to be added to the string manually.  Note that the value of terminal needs to be a whitespace separated string with the first item containing a recognized terminal name, here post or postscript.
        # Looking at Gnuplot.pm, new() automatically adds " eps" to the terminal value if output has the eps extension.  This explains the "eps redundant" error.
        my $outfile = $plotFile.'.eps';
        $chart->output("$outfile");
    }

    my @dataSets = ();
    my $ii = 0;
    
    my ($numCols,$numRows) = $inMat->dims;
    my @aXs = $inMat(0,:)->flat->list;
    
    for (my $ii=0;$ii<$numCols-1;$ii++){
        my @aYs = (($inMat($ii+1,:)->flat)+$ii*$vOffset)->list;
        $dataSets[$ii] = Chart::Gnuplot::DataSet->new(
        xdata => \@aXs,
        ydata => \@aYs,
        title => "trace $ii",
        style => "linespoints",
        pointtype => 1,             # +sign
        );
    }
    
    if ($verbose>=4) {
        print Data::Dump::dump($chart), "\n";
    }
    
    # Plot the datasets on the devices:
    if (!$useTerminal){
        $chart->plot2d(@dataSets);
    } else {
        my $pid = fork();
        if( $pid == 0 ){
            # Zero is the child's PID,
            $chart->plot2d(@dataSets);  # This never returns.
            exit 0;
        }
        # Non-zero is the parent's.
    }


}


sub Plot3D {
    
    ## A quick test plotting function.  Initial args must be in  groups of four, matching pdl pairs followed by a label string.  After the last group, one or two string args may be passed.  The first will be taken to be the plot title, and the second the name of a file to which the plot will be written.  If the filename starts with the string "ONLY", plotting to the terminal is suppressed.
    
    my $nargs = @_;
    if ($nargs < 3){croak "Plot:  At least 3 pdl vector args must be passed.\n"}
    
    my ($plotTitle,$plotFile) = ('','');
    my $lastArg = $_[$nargs-1];
    if (ref(\$lastArg) eq 'SCALAR'){
        if ($nargs%4 == 2){
            $plotFile = $lastArg;
            $plotTitle = $_[$nargs-2];
            pop @_; pop @_;
        }elsif ($nargs%4 == 1){
            $plotTitle = $lastArg;
            pop @_;
        }
    }else{  # last arg is not a scalar
        if ($nargs%4 != 3){croak "Plot: pdls must come in triples.\n"}
        else {push(@_,'')}
    }
    my $numTraces = @_;
    $numTraces /= 4;
    
    if ($verbose>=1){print "In Plot($plotFile)\n"}
    
    my $useTerminal = (substr($plotFile,0,4) ne "ONLY");
    if (!$useTerminal){$plotFile = substr($plotFile,4)}
    
    if ($verbose>=3){print "useTerminal=$useTerminal\n"}
    
    my ($xMin,$yMin,$zMin) = map {$inf} (0..2);
    my ($xMax,$yMax,$zMax) = map {$neginf} (0..2);
    
    my @dataSets = ();
    for (my $ii=0;$ii<$numTraces;$ii++) {
        my ($xArg,$yArg,$zArg,$labelArg) = (shift,shift,shift,shift);
        
        if ($verbose>=3){pq($ii,$xArg,$yArg,$zArg,$labelArg)}
        
        my $txMin = $xArg->min;
        my $tyMin = $yArg->min;
        my $tzMin = $zArg->min;
        
        if ($txMin < $xMin){$xMin = $txMin}
        if ($tyMin < $yMin){$yMin = $tyMin}
        if ($tzMin < $zMin){$zMin = $tzMin}
        
        my $txMax = $xArg->max;
        my $tyMax = $yArg->max;
        my $tzMax = $zArg->max;
        
        if ($txMax > $xMax){$xMax = $txMax}
        if ($tyMax > $yMax){$yMax = $tyMax}
        if ($tzMax > $zMax){$zMax = $tzMax}
        
        my @aXs = $xArg->list;
        my @aYs = $yArg->list;
        my @aZs = $zArg->list;
        
        $dataSets[$ii] = Chart::Gnuplot::DataSet->new(
        xdata => \@aXs,
        ydata => \@aYs,
        zdata => \@aZs,
        title => $labelArg,
        style => "linespoints",
        );
    }
    
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
    $zMin   = $cz-$range/2;
    $zMax   = $cz+$range/2;
    
    if ($verbose>=3){pq($range,$xMin,$xMax,$yMin,$yMax,$zMin,$zMax)}
    
    # Create chart object and specify its properties:
    my $chart = Chart::Gnuplot->new(
    title   => "$plotTitle",
    xlabel  => "X",
    ylabel  => "Y",
    zlabel  => "Z",
    view    => "equal xyz",
    xyplane => "at $zMin",
    #xrange  => "$xMin, $xMax",
    #yrange  => "$yMin, $yMax",
    #zrange  => "$zMin, $zMax",
    );
    
    
    if ($useTerminal) {
        $chart->terminal("x11 nopersist size 800,800");
        #$chart->terminal("x11 persist size 800,800");
        #$chart->terminal("x11 size 800,800");
        # 800,618 is 8.5x11 in landscape orientation.
        
        # See Gnuplot_5.2.pdf  Search for X11.
    } else {
        $chart->terminal("postscript enhanced color size 10,7");
        # Default is 10" x 7" (landscape).
        # Terminal defaults to enhanced color if not set, but if it is set, as here to set size, enhanced color needs to be added to the string manually.  Note that the value of terminal needs to be a whitespace separated string with the first item containing a recognized terminal name, here post or postscript.
        # Looking at Gnuplot.pm, new() automatically adds " eps" to the terminal value if output has the eps extension.  This explains the "eps redundant" error.
        my $outfile = $plotFile.'.eps';
        $chart->output("$outfile");
    }
    
    $chart->xrange(["$xMin", "$xMax"]);
    $chart->yrange(["$yMin", "$yMax"]);
    $chart->zrange(["$zMin", "$zMax"]);
    
    if ($verbose>=5) {
        print Data::Dump::dump($chart), "\n";
    }
    
    # =====================
    
    # Plot the datasets on the devices:
    # Plot the datasets on the devices:
    if (0){
        $chart->plot3d(@dataSets);
    }
    elsif (!$useTerminal){
        $chart->plot3d(@dataSets);
    } else {
        my $pid = fork();
        # This is really strange syntax, but that's what they say!
        #print "After fork, pid=$pid\n";
        if( $pid == 0 ){
            # Zero is the child's PID,
            #print "In child, before plotting, pid=$pid\n";
            #my $x = sin(7);
            #pq($x);
            #exit 0;
            $chart->plot3d(@dataSets); # Somehow this call, which does run, never returns here.
            
            #sleep(10);
            #$chart->terminal("x11 close");
            #print "In child, after plotting, pid=$pid\n";
            exit 0;
        }
        # Non-zero is the parent's.
        #sleep(0.1);
        # Sleep long enough for the window to complete.
        #print "In parent, after if, pid=$pid\n";
        #waitpid($pid, 0);  # This should be the correct way, but it never comes back!
        #waitpid(0, 0);  # This should be the correct way, but it never comes back!
        #waitpid(-1, 0);  # This should be the correct way, but it never comes back!
        # Hang around until the window completes.
        
        # See https://en.wikipedia.org/wiki/Fork_%28operating_system%29 for this standard bit of code, including waitpid().  But, in our case, $chart->plot3d(@dataSets) is presumably exec'ing the plot maintenance code, which among other things, keeps it live for rotation or resizing.
    }
    #die;
}

return 1;

=begin comment
 From Chart/Gnuplot/Util.pm
 
 sub _lineType
 {
	my ($type) = @_;
	return($type) if ($type =~ /^\d+$/);
 
	# Indexed line type of postscript terminal of gnuplot
	my %type = (
 solid          => 1,
 longdash       => 2,
 dash           => 3,
 dot            => 4,
 'dot-longdash' => 5,
 'dot-dash'     => 6,
 '2dash'        => 7,
 '2dot-dash'    => 8,
 '4dash'        => 9,
	);
	return($type{$type});
 }
 
 
 # Convert named line type to indexed line type of gnuplot
 # This may subjected to change when postscript/gnuplot changes its convention
 sub _pointType
 {
	my ($type) = @_;
	return($type) if ($type =~ /^\d+$/);
 
	# Indexed line type of postscript terminal of gnuplot
	my %type = (
 dot               => 0,
 plus              => 1,
 cross             => 2,
 star              => 3,
 'dot-square'      => 4,
 'dot-circle'      => 6,
 'dot-triangle'    => 8,
 'dot-diamond'     => 12,
 'dot-pentagon'    => 14,
 'fill-square'     => 5,
 'fill-circle'     => 7,
 'fill-triangle'   => 9,
 'fill-diamond'    => 13,
 'fill-pentagon'   => 15,
 square            => 64,
 circle            => 65,
 triangle          => 66,
 diamond           => 68,
 pentagon          => 69,
 'opaque-square'   => 70,
 'opaque-circle'   => 71,
 'opaque-triangle' => 72,
 'opaque-diamond'  => 74,
 'opaque-pentagon' => 75,
	);
	return($type{$type});
 }
 
 
 # https://metacpan.org/pod/Chart::Gnuplot#xtics,-ytics,-ztics
 
 Chart Options Not Mentioned Above
 
 If Chart::Gnuplot encounters options not mentions above, it would convert them to Gnuplot set statements. E.g. if the chart object is
 
 $chart = Chart::Gnuplot->new(
 ...
 foo => "FOO",
 );
 
 the generated Gnuplot statements would be:
 
 ...
 set foo FOO
 
 This mechanism lets Chart::Gnuplot support many features not mentioned above (such as "cbrange", "samples", "view" and so on).
 
 
 All the details are in the gnuplot 5.2 manual.  The discussion of view (and equal axes) starts on p. 181.
 
 Syntax:
 set view <rot_x>{,{<rot_z>}{,{<scale>}{,<scale_z>}}}
 set view map {scale <scale>}
 set view {no}equal {xy|xyz}
 set view azimuth <angle>
 show view
 
 set view equal xyz
 
 
 The set xyplane command adjusts the position at which the xy plane is drawn in a 3D plot. The synonym "set ticslevel" is accepted for backwards compatibility.
 Syntax:
 
 gnuplot 5.2 191
 set xyplane at <zvalue>
 set xyplane relative <frac>
 set ticslevel <frac>        # equivalent to set xyplane relative
 show xyplane
 The form set xyplane relative <frac> places the xy plane below the range in Z, where the distance from the xy plane to Zmin is given as a fraction of the total range in z. The default value is 0.5. Negative values are permitted, but tic labels on the three axes may overlap.
 The alternative form set xyplane at <zvalue> fixes the placement of the xy plane at a specific Z value regardless of the current z range. Thus to force the x, y, and z axes to meet at a common origin one would specify set xyplane at 0.
 See also set view (p. 181), and set zeroaxis (p. 193).
 
 =end comment
 =cut

