#!/usr/bin/perl

#############################################################################
## Name:			RUtils::Plot
## Purpose:			Quick plotting functions
## Author:			Rich Miller
## Modified by:
## Created:			2017/10/27
## Modified:		2019/3/4
## RCS-ID:
## Copyright:		(c) 2017 and 2019 Rich Miller
## License:			This program is free software; you can redistribute it and/or
##					modify it under the same terms as Perl itself
#############################################################################

# syntax:  use RUtils::Plot;

### WARNING: If the calling program does not stay alive long enough, these plots sometimes don't happen.  If you put sleep(2) after the call, that usually fixes things.  I don't understand this, since the plot is supposed to fork off, and thereafter be independent.

package RUtils::Plot;

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
use Data::Dump;
use Scalar::Util qw(looks_like_number);

use RUtils::Print;

my $inf    = 9**9**9;
my $neginf = -9**9**9;
my $nan    = -sin(9**9**9);

## See extensive comments at the end of this file.


sub Plot {
    # my ($x0,$y0,label0[,...,$xn,$yn,$labeln,$title,$optsRef])
    ## A quick test plotting function.  Initial args must be in  groups of three, matching pdl vector pairs followed by a label string.  After the last group, one or two string args may be passed.  If the last is a hash reference, it will be taken to be plot options as understood by gnuplot, and the next last, if there is one, will be taken to be the plot title.  If there are no options, and the last arg is a string, it will be used as the plot title.
    
    my $callingError = "CALLING ERROR: Plot([\$x0,]\$y0,[\$label0,...,\$xn,\$yn,\$labeln,\$title,\$optsRef]).  If only the first pair of vectors is passed, the label may be omitted.\n";
    
    my $nargs = @_;
    if ($nargs < 1){croak $callingError}
    
    my ($rPassedOpts,%passedOpts);
    my ($plotTitle,$plotFile) = ('','');

    # Strange the way ref works.
    #my $lastArg;
    #my $str = ref($lastArg);pq($str);    # Tests correctly for HASH
    #my $tStr = ref(\$lastArg);pq($tStr);  # Tests correctly for SCALAR

    if (ref($_[-1]) eq 'HASH'){
        #print "A\n";
        $rPassedOpts = pop;
        #print "rPassedOpts=$rPassedOpts\n";
        %passedOpts = %$rPassedOpts;
        #print "passedOpts=%passedOpts\n";
        #print "@_\n";
    }
    if (ref(\$_[-1]) eq 'SCALAR'){
        #print "B\n";
        $plotTitle  = pop;
        #pq($plotTitle);print "@_\n";
    }
    $nargs  = @_;
    if ($nargs == 1){
        #print "C\n";
        $nargs = unshift(@_,sequence($_[0]->nelem));
        #print "@_\n";
    }
    if ($nargs == 2){
        #print "D\n";
        $nargs = push @_, "";
        #print "@_\n";
    }
    if ($nargs%3 != 0){croak $callingError}
    
    
    # Deal with the options. See https://stackoverflow.com/questions/350018/how-can-i-combine-hashes-in-perl:
    
    my %opts = (size=>"500,400",
                xlabel=>"Independent Variable",
                ylabel=>"Dependent Variable",
                outfile=>"");
    
    #pq(\%opts);
    #pq(\%passedOpts);
    
    # Use passed opts to overwrite locals:
    @opts{keys %passedOpts} = values %passedOpts;
    #pq(\%opts);
    
    my $terminalString = "x11 size ".$opts{size};
    #my $terminalString = "x11 persist size ".$opts{size};
    #pq($terminalString);
    
    # So now the number of args is evenly divisible by 3.
    my $numTraces = @_;
    $numTraces /= 3;
    #pq($numTraces);
    
    #if ($verbose){print "In Plot($plotFile)\n"}
    
    #my $useTerminal = (substr($plotFile,0,4) ne "ONLY");
    #if (!$useTerminal){$plotFile = substr($plotFile,4)}
    my $useTerminal = ($opts{outfile} eq "")?1:0;
    
    #if ($verbose){pq($useTerminal)}
    
    # Create chart object and specify its properties:
    my $chart = Chart::Gnuplot->new(
        title  => "$plotTitle",
    );
    
    if ($opts{gnuplot}){$chart->gnuplot($opts{gnuplot})}

    $chart->xlabel($opts{xlabel});
    $chart->ylabel($opts{ylabel});
    
    if ($useTerminal) {
        $chart->terminal($terminalString);
        #$chart->terminal("x11 persist size 1000,800");
        # 800,618 is 8.5x11 in landscape orientation.
    } else {
        $chart->terminal("postscript enhanced color size 10,7");
        # Default is 10" x 7" (landscape).
        # Terminal defaults to enhanced color if not set, but if it is set, as here to set size, enhanced color needs to be added to the string manually.  Note that the value of terminal needs to be a whitespace separated string with the first item containing a recognized terminal name, here post or postscript.
        # Looking at Gnuplot.pm, new() automatically adds " eps" to the terminal value if output has the eps extension.  This explains the "eps redundant" error.
        $opts{outfile} = $opts{outfile}.'.eps';
        #my $outfile = $plotFile.'.eps';
        #$chart->output("$outfile");
    }
    
    
    my @dataSets = ();
    for (my $ii=0;$ii<$numTraces;$ii++) {
        my ($xArg,$yArg,$labelArg) = (shift,shift,shift);
        
        if ($verbose){pq($ii,$xArg,$yArg,$labelArg)}
        
        my @aXs = $xArg->list;
        my @aYs = $yArg->list;
        
        $dataSets[$ii] = Chart::Gnuplot::DataSet->new(
        xdata => \@aXs,
        ydata => \@aYs,
        title => $labelArg,
        style => "linespoints",
        );
    }
    
    if ($verbose) {
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
    #my ($inMat[,$vOffset][,$plotTitle][,$rPassedOpts]) = @_;
    
    ## A quick test plotting function.  Plots the later columns of the matrix against the first column with the desired vertical offset between traces.
    
    my $callingError = "CALLING ERROR: PlotMat(\$inMat[,\$vOffset][,\$plotTitle][,\$rOpts]).  \$inMat must be a 2-d pdl.";

    my $nargs = @_;
    if ($nargs < 1){croak $callingError}
    
    my ($inMat,$vOffset);
    my ($plotTitle,$plotFile);
    my ($rPassedOpts,%passedOpts);
    
    if (ref($_[-1]) eq 'HASH'){
        #print "A\n";
        $rPassedOpts = pop;
        %passedOpts = %$rPassedOpts;
        #print "passedOpts=%passedOpts\n";
        #print "@_\n";
    }
    if (ref(\$_[-1]) eq 'SCALAR'){
        #print "B\n";
        if (!looks_like_number($_[-1])){
            $plotTitle  = pop;
            #pq($plotTitle);
            #print "@_\n";
        }
    }
    if (ref(\$_[-1]) eq 'SCALAR'){
        #print "C\n";
        if (looks_like_number($_[-1])){
            $vOffset  = pop;
            #pq($vOffset);
            #print "@_\n";
        }
    }
    if (ref($_[-1]) eq 'PDL'){
        #print "D\n";
        $inMat  = pop;
        #pq($inMat);
        #print "@_\n";
    } else {croak $callingError}
    
    if (!defined($plotTitle)){$plotTitle = "PlotMat"}
    if (!defined($vOffset)){$vOffset = 0}
    
    #pq($inMat,$vOffset,$plotTitle);
    
    # Deal with the options.
    
    my %opts = (size=>"500,400",
    xlabel=>"Independent Variable",
    ylabel=>"Dependent Variable",
    outfile=>"");
    
    #pq(\%opts);
    #pq(\%passedOpts);
    
    # Use passed opts to overwrite locals:
    @opts{keys %passedOpts} = values %passedOpts;
    #pq(\%opts);
    
    my $terminalString = "x11 size ".$opts{size};
    #my $terminalString = "x11 persist size ".$opts{size};
    #pq($terminalString);
    
    
    #my $useTerminal = (substr($plotFile,0,4) ne "ONLY");
    #if (!$useTerminal){$plotFile = substr($plotFile,4)}
    my $useTerminal = ($opts{outfile} eq "")?1:0;
    
    #if ($verbose){pq($useTerminal)}
    
    # Create chart object and specify its properties:
    my $chart = Chart::Gnuplot->new(
    title  => "$plotTitle",
    );
    
    if ($opts{gnuplot}){$chart->gnuplot($opts{gnuplot})}

    $chart->xlabel($opts{xlabel});
    $chart->ylabel($opts{ylabel});
    
    if ($useTerminal) {
        $chart->terminal($terminalString);
        #$chart->terminal("x11 persist size 1000,800");
        # 800,618 is 8.5x11 in landscape orientation.
    } else {
        $chart->terminal("postscript enhanced color size 10,7");
        # Default is 10" x 7" (landscape).
        # Terminal defaults to enhanced color if not set, but if it is set, as here to set size, enhanced color needs to be added to the string manually.  Note that the value of terminal needs to be a whitespace separated string with the first item containing a recognized terminal name, here post or postscript.
        # Looking at Gnuplot.pm, new() automatically adds " eps" to the terminal value if output has the eps extension.  This explains the "eps redundant" error.
        $opts{outfile} = $opts{outfile}.'.eps';
        #my $outfile = $plotFile.'.eps';
        #$chart->output("$outfile");
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
        title => "column $ii",
        style => "linespoints",
        pointtype => 1,             # +sign
        );
    }
    
    if ($verbose) {
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
    
    # my ($x0,$y0,$z0,label0[,...,$xn,$yn,$zn,$labeln,$title,$optsRef])
    ## A quick test plotting function.  Initial args must be in  groups of four, matching pdl vector pairs followed by a label string.  After the last group, one or two string args may be passed.  If the last is a hash reference, it will be taken to be plot options as understood by gnuplot, and the next last, if there is one, will be taken to be the plot title.  If there are no options, and the last arg is a string, it will be used as the plot title.
    
    my $callingError = "CALLING ERROR: Plot([\$x0,]\$y0,\$z0,[\$label0,...,\$xn,\$yn,\$zn,\$labeln,\$title,\$optsRef]).  If only the first triple of vectors is passed, the label may be omitted.\n";
    
    my $nargs = @_;
    if ($nargs < 1){croak $callingError}
    
    my ($rPassedOpts,%passedOpts);
    my ($plotTitle,$plotFile);
    
    if (ref($_[-1]) eq 'HASH'){
        #print "A\n";
        $rPassedOpts = pop;
        #print "rPassedOpts=$rPassedOpts\n";
        %passedOpts = %$rPassedOpts;
        #print "passedOpts=%passedOpts\n";
        #print "@_\n";
    }
    if (ref(\$_[-1]) eq 'SCALAR'){
        #print "B\n";
        $plotTitle  = pop;
        #pq($plotTitle);print "@_\n";
    }
    $nargs  = @_;
    if ($nargs == 2){
        #print "C\n";
        $nargs = unshift(@_,sequence($_[0]->nelem));
        #print "@_\n";
    }
    if ($nargs == 3){
        #print "D\n";
        $nargs = push @_, "";
        #print "@_\n";
    }
    if ($nargs%4 != 0){croak  $callingError}
    
    # Deal with the options. See https://stackoverflow.com/questions/350018/how-can-i-combine-hashes-in-perl:
    
    my %opts = (size=>"500,500",
    xlabel=>"x-axis",
    ylabel=>"y-axis",
    zlabel=>"z-axis",
    view=>"equal xyz",
    xyplane=> "relative 0.1",
    outfile=>"",);
    
    #pq(\%opts);
    #pq(\%passedOpts);
    
    # Use passed opts to overwrite locals:
    @opts{keys %passedOpts} = values %passedOpts;
    #pq(\%opts);
    
    #my $terminalString = "x11 nopersist size 800,800";
    #my $terminalString = "x11 persist size ".$opts{size};
    my $terminalString = "x11 size ".$opts{size};
    #pq($terminalString);
    
    # So now the number of args is evenly divisible by 3.
    my $numTraces = @_;
    $numTraces /= 4;
    #pq($numTraces);
    
    #if ($verbose){print "In Plot($plotFile)\n"}
    
    #my $useTerminal = (substr($plotFile,0,4) ne "ONLY");
    #if (!$useTerminal){$plotFile = substr($plotFile,4)}
    my $useTerminal = ($opts{outfile} eq "")?1:0;
    if ($verbose){pq($useTerminal)}
    
    # Create chart object and specify its properties:
    my $chart = Chart::Gnuplot->new(
    title  => "$plotTitle",
    );
    
    if ($opts{gnuplot}){$chart->gnuplot($opts{gnuplot})}

    $chart->xlabel($opts{xlabel});
    $chart->ylabel($opts{ylabel});
    $chart->zlabel($opts{zlabel});
    $chart->view($opts{view});
    
    
    if ($useTerminal) {
        $chart->terminal($terminalString);
        #$chart->terminal("x11 persist size 1000,800");
        # 800,618 is 8.5x11 in landscape orientation.
    } else {
        $chart->terminal("postscript enhanced color size 10,7");
        # Default is 10" x 7" (landscape).
        # Terminal defaults to enhanced color if not set, but if it is set, as here to set size, enhanced color needs to be added to the string manually.  Note that the value of terminal needs to be a whitespace separated string with the first item containing a recognized terminal name, here post or postscript.
        # Looking at Gnuplot.pm, new() automatically adds " eps" to the terminal value if output has the eps extension.  This explains the "eps redundant" error.
        $opts{outfile} = $opts{outfile}.'.eps';
        #my $outfile = $plotFile.'.eps';
        #$chart->output("$outfile");
    }
    
    #my %testChart = %$chart;
    #pq(\%testChart);
    
    my ($xMin,$yMin,$zMin) = map {$inf} (0..2);
    my ($xMax,$yMax,$zMax) = map {$neginf} (0..2);
    
    my @dataSets = ();
    for (my $ii=0;$ii<$numTraces;$ii++) {
        my ($xArg,$yArg,$zArg,$labelArg) = (shift,shift,shift,shift);
        
        if ($verbose){pq($ii,$xArg,$yArg,$zArg,$labelArg)}
        
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
        
        #my $ref = ref($dataSets[$ii]);
        #pq($ref);

        if ($verbose){print Data::Dump::dump($dataSets[$ii]), "\n";}
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
    
    
    $chart->xrange(["$xMin", "$xMax"]);
    $chart->yrange(["$yMin", "$yMax"]);
    $chart->zrange(["$zMin", "$zMax"]);
    $chart->xyplane("at $zMin");
    
    if ($verbose) {
        print Data::Dump::dump($chart), "\n";
    }
    #die;
    # =====================
    
    # Plot the datasets on the devices:
    if (0){
        $chart->plot3d(@dataSets);
    }
    elsif (!$useTerminal){
        $chart->plot3d(@dataSets);
    } else {
        #print "Using terminal\n";
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
}

return 1;


__END__

=head1 NAME

RUtils::Plot - Quick PDL 2D and 3D plotting functions wrapping Gnuplot system calls.  If no system gnuplot is available, $optsRef->{gnuplot} may be set to point to a local copy.

=head1 SYNOPSIS

use RUtils::Plot;
  
Plot($x0,$y0,label0[,...,$xn,$yn,$labeln,$title,$optsRef]);

   Initial args must be in  groups of three, matching pdl vector pairs followed by a label string.  After the last group, one or two string args may be passed.  If the last is a hash reference, it will be taken to be plot options as understood by gnuplot, and the next last, if there is one, will be taken to be the plot title.  If there are no options, and the last arg is a string, it will be used as the plot title.
 
  
PlotMat($inMat[,$vOffset][,$plotTitle][,$rPassedOpts]);

   A quick test plotting function.  Plots the later columns of the matrix against the first column with the desired vertical offset between traces.
 
Plot3D($x0,$y0,$z0,label0[,...,$xn,$yn,$zn,$labeln,$title,$optsRef]);

   A quick test plotting function.  Initial args must be in  groups of four, matching pdl vector pairs followed by a label string.  After the last group, one or two string args may be passed.  If the last is a hash reference, it will be taken to be plot options as understood by gnuplot, and the next last, if there is one, will be taken to be the plot title.  If there are no options, and the last arg is a string, it will be used as the plot title.
   
   
=head1 WARNING

If the calling program does not stay alive long enough, these plots sometimes don't happen.  If you put sleep(2) after the call, that usually fixes things.  I don't understand this, since the plot is supposed to fork off, and thereafter be independent.
 
=head1 EXPORT

plot, plotMat, and plot3D.


=head1 GNUPLOT REFERENCE (FOR CONVENIENCE)

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
 
 
 L<https://metacpan.org/pod/Chart::Gnuplot#xtics,-ytics,-ztics>
 
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
 

=head1 AUTHOR

Rich Miller, E<lt>rich@ski.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2019 by Rich Miller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.28.1 or,
at your option, any later version of Perl 5 you may have available.


=cut





