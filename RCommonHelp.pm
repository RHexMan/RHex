#!/usr/bin/perl -w

# RCommonHelp.pm

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

package RCommonHelp;

## All the common dialogs for the help menu.

use warnings;
use strict;

our $VERSION='0.01';

use Exporter 'import';
our @EXPORT = qw(OnLineEtc OnVerboseParam OnGnuplotView OnGnuplotViewCont);

use Tk::DialogBox;

# Functions ==============

# Show the Help->About Dialog Box
sub OnLineEtc {
    # Construct the DialogBox
#    my $params = $mw->DialogBox(
    my $params = $main::mw->DialogBox(
		   -title=>"Line, Leader, Tippet & Fly Params",
		   -buttons=>["OK"]
		   );

    # Now we need to add a Label widget so we can show some text.  The
    # DialogBox is essentially an empty frame with no widgets in it.
    # You can images, buttons, text widgets, listboxes, etc.
    $params->add('Label',
		-anchor=>'w',
		-justify=>'left',
		-text=>qq{
FLY LINE:

totalLength - The combined length in feet of the part of the fly line outside the tip guide, the
	leader, and the tippet.  It must be positive. Typical range is [10,50].

nominalWeight - Fly line nominal weight in grains per foot. For tapered lines, this is supposed to
	be the average grains per foot of the first 30 feet of line.  Must be non-negative. The typical
	range [1,15].  About 15 grains make one gram, and 437.5 grains make one ounce.
    
estimatedDensity - Fly line density. Non-dimensional.  Used for computing diameters when only
	weights per foot are known.  Must be positive.  Typical range is [0.5,1.5].  Densities less
	than 1 float in fresh water, greater than 1 sink.

nominalDiameter - In inches.  Used only for level lines.  Must be non-negative. Typical range is
	[0.030,0.090].

coreDiameter - The braided or twisted core of a coated fly line provides most of the tensile
	strength and elastic modulus.  The diameter in inches.  Must be non-negative.  Typical range
	is [0.010,0.050].
    
coreElasticModulus - Also known as Young\'s Modulus, in pounds per square inch.  Dependent on the
	type of material that makes up the core.  Must be non-negative.  Typical range is [1e5,4e5],
	that is, [100,000 - 400,000].
    
dampingModulus - In pounds per square inch.  Dependent on the material type.  Must be non-negative.
	A hard number to come by in the literature.  However, it is very important for the stability of
	the numerical calculation.  Values much different from 1 slow the solver down a great deal,
	while those much above 10 lead to anomalies during stripping.


LEADER:
    
length - In feet. Must be non-negative.  Typical range is [5,15].

weight - In grains per foot.  Used only for level leaders.  Weight must be non-negative. Typical
	range for sink tips is [7,18].

diameter - In inches.  Used only for level leaders.  Must be positive. Typical range is
	[0.004,0.050], with sink tips in the range [0.020,0.050].


TIPPET (always level):

length - In feet. Must be non-negative. Typical range is [2,12].

diameter - In inches.  Must be non-negative. Typical range is [0.004,0.012]. Subtract a tippet
	X value from 0.011 inches to convert X\'s to inches.


FLY:

weight - In grains. Must be non-negative.  Typical range is [0,15], but a very heavy intruder
	might be as much as 70.

nominalDiameter - In inches.  To account for the drag on a fly, we estimate an effective
	drag diameter and effective drag length.  Nominal diameter must be non-negative. Typical range
	is [0.1,0.25].

nominalLength - In inches.  Must be non-negative. Typical range is [0.25,1].

estimatedDisplacement - In cubic inches.  To account for buoyancy, we need to estimate the actual
	volume displaced by the fly materials.  This is typically very much less than the drag volume
	computed from the drag diameter and length described above.  Fly nom volume must be non-
	negative. On small flies this may be just a little more than the volume of the hook metal.
	Typical range is [0,0.005].
}
		)->pack;

    $params->Show();
}


sub OnVerboseParam {
    # Construct the DialogBox
    my $params = $main::mw->DialogBox(
		   -title=>"Verbose Param",
		   -buttons=>["OK"]
		   );

    # Now we need to add a Label widget so we can show some text.  The
    # DialogBox is essentially an empty frame with no widgets in it.
    # You can images, buttons, text widgets, listboxes, etc.
    $params->add('Label',
		-anchor=>'w',
		-justify=>'left',
		-text=>qq{
VERBOSE:

verbose - Allows you to specify the amount of textual information that is displayed during an integrator run.  You
	can set the value to any of the integers in the range 0 to 3 inclusive.  The higher the number, the more
	information displayed.  Numbers less than or equal to 2 are essentially cost free, and setting verbose to 2 is
	generally the best choice, since it gives you a satisfying graphic depiction of the progress of the
	calculation.  This, among other things, lets you chose opportune moments to pause the run and view a plot of
	the swing up to that time.  Verbose set to 0 prints only the most general indication that the program is
	running or stopped, as well as actual error messages that mean that the calculation cannot start or proceed for
	some reason, typically because you have used unallowed parameter values, but also sometime because there is a
	programming bug that needs to be corrected.  Verbose set to 1 additionally prints warnings about typical ranges
	of parameters.  Verbose set to 2 prints all these things, plus indicating progress through the run setup
	procedure, plus the progress graphic and a few more details about computation times and the like.  One
	interesting special feature, is that if you have a level leader, its still water sink rate is computed.  It is
	often of interest to compare this number to the manufacturer\'s advertised value.  For verbose less than or
	equal to 2, all the output appears in the status pane on the control panel.  There is a scroll bar on the right
	hand edge of the pane that lets you look back at text that passed by earlier.

Verbose equal to 3 is an entirely different animal.  It generates a lot more output, which includes, at each
	integrator test step, a listing of all the forces exerted on the segment centers of gravity, including
	gravitation, buoyancy, and fluid drag, as well as the tension and dissipative forces acting along the segments.
	All these forces balance against inertial forces due to the segment masses to determine the dynamics of the
	swing.  Printing all this slows down the calculation quite a bit, but can be fascinating to look at, especially
	if something counter intuitive is happening.  To accomodate all this output, the program is set up print it in
	the much larger Terminal application window that is automatically created when RHexSwing3D is launched.  In
	addition to capacity, the terminal window has two very important other advantages:  it is searchable with the
	standard mac mechanisms, and is savable to a file, so you can keep the run details for as long as you want.
}
		)->pack;

    $params->Show();
}


sub OnGnuplotView {
    # Construct the DialogBox
    my $params = $main::mw->DialogBox(
		   -title=>"Gnuplot View",
		   -buttons=>["OK"]
		   );

    # Now we need to add a Label widget so we can show some text.  The
    # DialogBox is essentially an empty frame with no widgets in it.
    # You can images, buttons, text widgets, listboxes, etc.
    $params->add('Label',
		-anchor=>'w',
		-justify=>'left',
		-text=>qq{

GNUPLOT VIEW MANIPULATIONS AND MOUSE AND KEY BINDINGS

For better inspection, the view of 3D plots drawn by gnuplot in X11 windows can be changed in real time by the user. The collection of
traces comprising a plot can be rotated in space, translated, and zoomed.  These actions are effected by means of various mouse
controls and keyboard key combinations.

To rotate, simply hold and drag.  That is, position the cursor over any part of the white portion of the plot window (called the canvas).
The arrow cursor will turn into cross-hairs.  Hold down the primary mouse button and the cursor will change to a rotation symbol.  Continue
holding and drag in any direction.  The plot image will appear to rotate in space.  When you release the button, the image will remain in
its rotated state.  You can re-rotate any number of times.

This is easy enough, but when you think in detail about what\'s happening, it can be confusing.  In fact, the rule is simple, but to state
it we need some preliminaries.  Our plots contain the image of a ticked square parallel to the (x,y)-plane, but typically not containing the
coordinate origin (0,0,0), and a ticked line segment parallel to the z-axis, but again not usually containing the origin.  The plot box is
an imaginary construct, the rectanglular solid with edges parallel to the coordinate axes just large enough to contain the ticked square and
the ticked segment.  Gnuplot displays only the parts of traces that are contained in the plot box.  Any other plot parts are rendered
invisible. When RHex first draws a plot, all the parts of all the traces are contained in the plot box and are visible.  No rotation will
change that situation.

Now for the rule:  Pure horizontal cursor motion (relative to the canvas) rotates the image around the axis parallel to a canvas vertical
that passes through the geometric center of the plot box.  The rotation is like a merry-go-round.  Vertical cursor motion rotates the image
around an axis parallel to the canvas horizontal that passes through the plot box center.  This rotation is like a ferris wheel that you are
looking at straight on.

If you try these motions, you will see that they seem to work as described, but with some sloppiness, which is actually due to your hand not
moving the cursor exactly right.  Gnuplot has made it it possible to eliminate these errors. The right and left and up and down arrow keys
have been bound to have the same effect as the cooresponding cursor motions. Each keypress makes a small rotation.  Holding a key down
generates a steady rotation, perfectly aligned.

The gnuplot implementations for translation and zoom, although effective, are unfortunately not as clearly comprehensible.  There is a
physical problem as well as a choice that, in retrospect, was not the right one.  The physical difficulty is that when things are translated,
they go away.  You also lose part of the image to the periphery when you zoom in.  This is in contrast to rotation, where, if you pick an
appropriate rotation center, things stay at least somewhere near where they started.

It is now generally understood that the most useful form of zoom is zoom-to-point, where the obvious implementation zooms in toward the
apparent location of the cursor.  Gnuplot does not offer this.  Instead, if you hold the 3rd mouse button (or the mouse wheel-as-button if
you have that) and drag horizontally to the right, you zoom in toward the center of the plot box, and if you drag to the left, you zoom back
out again.  This zoom is easy to comprehend, since the ticked square and line segments zoom along with the traces, just as you would expect.
At some point as you zoom in, the square and segment disappear off the canvas, so you can\'t read item coordinates.  But you can see the
traces in their elegant scalable vector graphic (SVG) form, which is generally just what you want.

At this point, what is need is a translation mechanism since you are almost never interested in looking at the plot box center, but rather
want to inspect some small region near the traces, and the way you would do that is to translate the region of interest to the plot box
center.  Gnuplot does provide translation, and although its form is not really the best, it will do.

What gnuplot does not do, but what it could have done, is provide a plot box translation.  Which is to say, have a mouse action that
causes the plot box itself, together with all its contents, to move in some direction across and finally completely off the canvas.
Instead, they leave the box in the same position on the canvas and translate the contents out of the plot box.  The labels on the ticks
change, so you known that this is happening.  Nonetheless, it is very disconcerting since parts of the traces suddenly disappear even though
they were nowhere near the edge of the canvas.  This is because these parts have passed through a(n ivisible) boundary plane of the plot box
and gnuplot has stopped drawing them.  Fortunately, when you have zoomed in close enough, the plot box bounding planes themselves move off
the canvas, so the disconcerting effect doesn\'t happen.

In any case, the way you do the translation is to rotate the mouse wheel  This will always translate the traces parallel to the y-axis,
however that axis may seem to point as a result of previous 3D rotations.  If you hold down the shift key while you rotate the mouse wheel,
the traces are translated parallel to the x-axis.  Unfortunately, there seems to be no mechanism for translating parallel to the z-axis, but
line-of-sight considerations mean you are always able to get your region of interest onto the line perpendicular to the canvas going through
the plot box center, which makes it visible under all zoom conditions.

Because translation, both the preferred and the gnuplot kinds, can move the traces completely out of view, you can get into a situation
where you don\'t know where your traces are.  In that case, you can always zoom way back out, and you will then find them.  But gnuplot
offers a very useful short cut.  Simply press <cmd-u> and your traces will jump back to full visibility in the plot box, without any change
having been made in zoom or rotation.
}
		)->pack;

    $params->Show();
}



sub OnGnuplotViewCont {
    # Construct the DialogBox
    my $params = $main::mw->DialogBox(
		   -title=>"Gnuplot View (Continued)",
		   -buttons=>["OK"]
		   );

    # Now we need to add a Label widget so we can show some text.  The
    # DialogBox is essentially an empty frame with no widgets in it.
    # You can images, buttons, text widgets, listboxes, etc.
    $params->add('Label',
		-anchor=>'w',
		-justify=>'left',
		-text=>qq{
GNUPLOT VIEW MANIPULATIONS AND MOUSE AND KEY BINDINGS (continued)

The manipulations described above will let you inspect your trace collections well enough for all practical purposes.  However,
gnuplot offers quite a few other manipulations that solve special problems.  I briefly mention three:

If you hold down the wheel button as if to zoom, but instead of dragging horizontally, drag vertically, an very strange apparent rotation
takes place.  But when you look at it more closely, you see that it is not a rotation at all, but rather a change in scaling of the z-axis
segment.  After such a scaling, angles and trace segment lengths no longer appear veritical, but, especially for very flat sets of traces,
magnification of z differences can be helpful.

If you hold down the secondary mouse button and drag horizontally, you will get an apparent clockwise or counterclockwise rotation of the
z-axis.  This brings in a new rotational degree of freedom.  All the previous rotations (holding the primary button and moving the mouse)
preserved the apparent canvas relative right-left orientation of the z-axis.  Holding the secondary button while dragging vertically has no
effect at all.

Holding down the control key while rotating the mouse button effects a different sort of zoom, where plot box doesn\'t move, but the scaling
as indicated by the tick labels changes, and the collection of traces zooms toward the vertical line throught the plot box center as you
zoom out, while more and more of the trace parts disappear through the plot box walls as you zoom in.  I dont like this zoom at all.


Finally, here is a complete list of the key and mouse bindings.  On the mac, all the letter options need to have the command key held while
pressing the letter key.

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
}
	)->pack;

    $params->Show();
}



# Required package return value:
1;

__END__


=head1 NAME

RCommonHelp - All the common dialogs for the help menu.

=head1 SYNOPSIS

use RCommonHelp;

=head1 EXPORT

OnLineEtc OnVerboseParam OnGnuplotView OnGnuplotViewCont

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


