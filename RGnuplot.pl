#line 1 "Chart/Gnuplot.pm"
package Chart::Gnuplot;
use strict;
use vars qw($VERSION);
use Carp;
use File::Copy qw(move);
use File::Temp qw(tempdir);
use Chart::Gnuplot::Util qw(_lineType _pointType _borderCode _fillStyle _copy);
$VERSION = '0.23';

# Constructor
sub new
{
    my ($class, %hash) = @_;

    # Create temporary file to store Gnuplot instructions
    if (!defined $hash{_multiplot})     # if not in multiplot mode
    {
        my $dirTmp = tempdir(CLEANUP => 1);
        ($^O =~ /MSWin/)? ($dirTmp .= '\\'): ($dirTmp .= '/');
        $hash{_script} = $dirTmp . "plot";
    }

    # Default terminal: postscript terminal with color drawing elements
    if (!defined $hash{terminal} && !defined $hash{term})
    {
        $hash{terminal} = "postscript enhanced color";
        $hash{_terminal} = 'auto';
    }

    # Default setting
    if (defined $hash{output})
    {
        my @a = split(/\./, $hash{output});
        my $ext = $a[-1];
        $hash{terminal} .= " eps" if ($hash{terminal} =~ /^post/ &&
            $ext eq 'eps');
    }

    my $self = \%hash;
    return bless($self, $class);
}


# Generic attribute methods
sub AUTOLOAD
{
    my ($self, $key) = @_;
    my $attr = our $AUTOLOAD;
    $attr =~ s/.*:://;
    return if ($attr eq 'DESTROY');        # ignore destructor
    $self->{$attr} = $key if (defined $key);
    return($self->{$attr});
}


# General set method
sub set
{
    my ($self, %opts) = @_;
    foreach my $opt (keys %opts)
    {
        ($opts{$opt} eq 'on')? $self->$opt('') : $self->$opt($opts{$opt});
    }
    return($self);
}


# Add a 2D data set to the chart object
# - used with multiplot
sub add2d
{
    my ($self, @dataSet) = @_;
    push(@{$self->{_dataSets2D}}, @dataSet);
}


# Add a 3D data set to the chart object
# - used with multiplot
sub add3d
{
    my ($self, @dataSet) = @_;
    push(@{$self->{_dataSets3D}}, @dataSet);
}


# Add a 2D data set to the chart object
# - redirect to &add2d
# - for backward compatibility
sub add {&add2d(@_);}


# Plot 2D graphs
# - call _setChart()
#
# TODO:
# - Consider using pipe instead of system call
# - support MS time format: %{yyyy}-%{mmm}-%{dd} %{HH}:%{MM}
sub plot2d
{
    my ($self, @dataSet) = @_;
    &_setChart($self, \@dataSet);

    my $plotString = join(', ', map {$_->_thaw($self)} @dataSet);
    open(GPH, ">>$self->{_script}") || confess("Can't write $self->{_script}");
    print GPH "\nplot $plotString\n";
    close(GPH);

    # Generate image file
    &execute($self);
    return($self);
}


# Plot 3D graphs
# - call _setChart()
#
# TODO:
# - Consider using pipe instead of system call
# - support MS time format: %{yyyy}-%{mmm}-%{dd} %{HH}:%{MM}
sub plot3d
{
    my ($self, @dataSet) = @_;
    &_setChart($self, \@dataSet);

    my $plotString = join(', ', map {$_->_thaw($self)} @dataSet);
    open(GPH, ">>$self->{_script}") || confess("Can't write $self->{_script}");
    print GPH "\nsplot $plotString\n";
    close(GPH);

    # Generate image file
    &execute($self);
    return($self);
}


# Plot multiple plots in one single chart
sub multiplot
{
    my ($self, @charts) = @_;
    &_setChart($self);
    &_reset($self);

    open(PLT, ">>$self->{_script}") || confess("Can't write $self->{_script}");

    # Emulate the title when there is background color fill
    if (defined $self->{title} && defined $self->{bg})
    {
        print PLT "set label \"$self->{title}\" at screen 0.5, screen 1 ".
            "center offset 0,-1\n";
    }

    if (scalar(@charts) == 1 && ref($charts[0]) eq 'ARRAY')
    {
        my $nrows = scalar(@{$charts[0]});
        my $ncols = scalar(@{$charts[0][0]});
        &_setMultiplot($self, $nrows, $ncols);
    
        for (my $r = 0; $r < $nrows; $r++)
        {
            for (my $c = 0; $c < $ncols; $c++)
            {
                my $chart = $charts[0][$r][$c];
                $chart->_script($self->{_script});
                $chart->_multiplot(1);
                delete $chart->{bg};

                my $plot;
                my @dataSet;
                if (defined $chart->{_dataSets2D})
                {
                    $plot = 'plot';
                    @dataSet = @{$chart->{_dataSets2D}};
                }
                elsif (defined $chart->{_dataSets3D})
                {
                    $plot = 'splot';
                    @dataSet = @{$chart->{_dataSets3D}};
                }

                &_setChart($chart, \@dataSet);
                open(PLT, ">>$self->{_script}") ||
                    confess("Can't write $self->{_script}");
                print PLT "\n$plot ";
                print PLT join(', ', map {$_->_thaw($self)} @dataSet), "\n";
                close(PLT);
                &_reset($chart);
            }
        }
    }
    else
    {
        # Start multi-plot
        &_setMultiplot($self);

        foreach my $chart (@charts)
        {
            $chart->_script($self->{_script});
            $chart->_multiplot(1);
            delete $chart->{bg};

            my $plot;
            my @dataSet;
            if (defined $chart->{_dataSets2D})
            {
                $plot = 'plot';
                @dataSet = @{$chart->{_dataSets2D}};
            }
            elsif (defined $chart->{_dataSets3D})
            {
                $plot = 'splot';
                @dataSet = @{$chart->{_dataSets3D}};
            }
        
            &_setChart($chart, \@dataSet);
            open(PLT, ">>$self->{_script}") ||
                confess("Can't write $self->{_script}");
            print PLT "\n$plot ";
            print PLT join(', ', map {$_->_thaw($self)} @dataSet), "\n";
            close(PLT);
            &_reset($chart);
        }
    }
    close(PLT);

    # Generate image file
    &execute($self);
    return($self);
}


# Pass generic commands
sub command
{
    my ($self, $cmd) = @_;

    open(PLT, ">>$self->{_script}") || confess("Can't write $self->{_script}");
    (ref($cmd) eq 'ARRAY')?
        (print PLT join("\n", @$cmd), "\n"):
        (print PLT "$cmd\n");
    close(PLT);
    return($self);
}


# Set how the chart looks like
# - call _setTitle(), _setAxisLabel(), _setTics(), _setGrid(), _setBorder(),
#        _setTimestamp()
# - called by plot2d() and plot3d()
sub _setChart
{
    my ($self, $dataSets) = @_;
    my @sets = ();

    # Orientation
    $self->{terminal} .= " $self->{orient}" if (defined $self->{orient});

    # Set canvas size
    if (defined $self->{imagesize})
    {
        my ($ws, $hs) = split(/,\s?/, $self->{imagesize});
        if (defined $self->{_terminal} && $self->{_terminal} eq 'auto')
        {
            # for post terminal
            if (defined $self->{orient} && $self->{orient} eq 'portrait')
            {
                $ws *= 7 if ($ws =~ /^([1-9]\d*)?0?(\.\d+)?$/);
                $hs *= 10 if ($hs =~ /^([1-9]\d*)?0?(\.\d+)?$/);
            }
            else
            {
                $ws *= 10 if ($ws =~ /^([1-9]\d*)?0?(\.\d+)?$/);
                $hs *= 7 if ($hs =~ /^([1-9]\d*)?0?(\.\d+)?$/);
            }
        }
        $self->{terminal} .= " size $ws,$hs";
    }

    # Prevent changing terminal in multiplot mode
    delete $self->{terminal} if (defined $self->{_multiplot});

    # Start writing gnuplot script
    my $pltTmp = $self->{_script};
    open(PLT, ">>$pltTmp") || confess("Can't write gnuplot script $pltTmp");

    # Set character encoding
    #
    # Quote from Gnuplot manual:
    # "Generally you must set the encoding before setting the terminal type."
    if (defined $self->{encoding})
    {
        print PLT "set encoding $self->{encoding}\n";
    }

    # Chart background color
    if (defined $self->{bg})
    {
        my $bg = $self->{bg};
        if (ref($bg) eq 'HASH')
        {
            print PLT "set object rect from screen 0, screen 0 to ".
                "screen 1, screen 1 fillcolor rgb \"$$bg{color}\"";
            print PLT " fillstyle solid $$bg{density}" if
                (defined $$bg{density});
            print PLT " behind\n";
        }
        else
        {
            print PLT "set object rect from screen 0, screen 0 to ".
                "screen 1, screen 1 fillcolor rgb \"$bg\" behind\n";
        }
        push(@sets, 'object');
    }

    # Plot area background color
    if (defined $self->{plotbg})
    {
        my $bg = $self->{plotbg};
        if (ref($bg) eq 'HASH')
        {
            print PLT "set object rect from graph 0, graph 0 to ".
                "graph 1, graph 1 fillcolor rgb \"$$bg{color}\"";
            print PLT " fillstyle solid $$bg{density}" if
                (defined $$bg{density});
            print PLT " behind\n";
        }
        else
        {
            print PLT "set object rect from graph 0, graph 0 to ".
                "graph 1, graph 1 fillcolor rgb \"$bg\" behind\n";
        }
        push(@sets, 'object');
    }

    # Set date/time data
    #
    # For xrange to work for time-sequence, time-axis ("set xdata time")
    # and timeformat ("set timefmt '%Y-%m-%d'") MUST be set BEFORE 
    # the range command ("set xrange ['2009-01-01','2009-01-07']")
    #
    # Thanks to Holyspell
    if (defined $self->{timeaxis})
    {
        my @axis = split(/,\s?/, $self->{timeaxis});
        foreach my $axis (@axis)
        {
            print PLT "set $axis"."data time\n";
            push(@sets, $axis."data");
        }

        foreach my $ds (@$dataSets)
        {
            if (defined $ds->{timefmt})
            {
                print PLT "set timefmt \"$ds->{timefmt}\"\n";
                last;
            }
        }
    }

    # Parametric plot
    foreach my $ds (@$dataSets)
    {
        # Determine if there is paramatric plot
        if (defined $ds->{func} && ref($ds->{func}) eq 'HASH')
        {
            $self->{parametric} = '';
            last;
        }
    }

    my $setGrid = 0;    # detect whether _setGrid has been run

    # Loop and process other chart options
    foreach my $attr (keys %$self)
    {
        if ($attr eq 'output')
        {
            print PLT "set output \"$self->{output}\"\n";
        }
        elsif ($attr eq 'title')
        {
            print PLT "set title ".&_setTitle($self->{title})."\n";
            push(@sets, 'title')
        }
        elsif ($attr =~ /^((x|y)2?|z)label$/)
        {
            print PLT "set $attr ".&_setAxisLabel($self->{$attr})."\n";
            push(@sets, $attr);
        }
        elsif ($attr =~ /^((x|y)2?|z|t|u|v)range$/)
        {
            if (ref($self->{$attr}) eq 'ARRAY')
            {
                # Deal with ranges from array reference
                if (defined $self->{timeaxis} &&
                    $self->{timeaxis} =~ /(^|,)\s*$1\s*(,|$)/)
                {
                    # $1-axis is a time axis
                    print PLT "set $attr ['".join("':'", @{$self->{$attr}}).
                        "']\n";
                }
                else
                {
                    print PLT "set $attr [".join(":", @{$self->{$attr}})."]\n";
                }
            }
            elsif ($self->{$attr} eq 'reverse')
            {
                print PLT "set $attr [*:*] reverse\n";
            }
            else
            {
                print PLT "set $attr $self->{$attr}\n";
            }
            push(@sets, $attr);
        }
        elsif ($attr =~ /^(x|y|x2|y2|z)tics$/)
        {
            if (defined $self->{$attr})
            {
                my ($axis) = ($attr =~ /^(.+)tics$/);
                print PLT "set $attr".&_setTics($self->{$attr})."\n";
                if (ref($self->{$attr}) eq 'HASH')
                {
                    if (defined ${$self->{$attr}}{labelfmt})
                    {
                        print PLT "set format $axis ".
                            "\"${$self->{$attr}}{labelfmt}\"\n";
                        push(@sets, 'format');
                    }
                    if (defined ${$self->{$attr}}{minor})
                    {
                        my $nTics = ${$self->{$attr}}{minor}+1;
                        print PLT "set m$axis"."tics $nTics\n";
                        push(@sets, "m$axis"."tics");
                    }
                }
                push(@sets, $attr);
            }
            else
            {
                print PLT "unset $attr\n";
            }
        }
        elsif ($attr eq 'legend')
        {
            print PLT "set key".&_setLegend($self->{legend})."\n";
            push(@sets, 'key');
        }
        elsif ($attr eq 'border')
        {
            if (defined $self->{border})
            {
                print PLT "set border";
                print PLT " ".&_borderCode($self->{border}->{sides}) if
                    (defined $self->{border}->{sides});
                print PLT &_setBorder($self->{border})."\n";
                push(@sets, 'border');
            }
            else
            {
                print PLT "unset border\n";
            }
        }
        elsif ($attr =~ /^(minor)?grid$/)
        {
            next if ($setGrid == 1);

            print PLT "set grid".&_setGrid($self)."\n";
            push(@sets, 'grid');
            $setGrid = 1;
        }
        elsif ($attr eq 'timestamp')
        {
            print PLT "set timestamp".&_setTimestamp($self->{timestamp})."\n";
            push(@sets, 'timestamp');
        }
        elsif ($attr eq 'terminal')
        {
            print PLT "set $attr $self->{$attr}\n";
        }
        # Non-gnuplot options / options specially treated before
        elsif (!grep(/^$attr$/, qw(
                gnuplot
                convert
                encoding
                imagesize
                orient
                bg
                plotbg
                timeaxis
            )) &&
            $attr !~ /^_/)
        {
            (defined $self->{$attr} && $self->{$attr} ne '')?
                (print PLT "set $attr $self->{$attr}\n"):
                (print PLT "set $attr\n");
            push(@sets, $attr);
        }
    }

    # Write labels
	my $isLabelSet = 0;
    foreach my $label (@{$self->{_labels}})
    {
        print PLT "set label"."$label\n";
		push(@sets, "label") if ($isLabelSet == 0);
		$isLabelSet = 1;
    }

    # Draw arrows
	my $isArrowSet = 0;
    foreach my $arrow (@{$self->{_arrows}})
    {
        print PLT "set arrow"."$arrow\n";
		push(@sets, "arrow") if ($isArrowSet == 0);
		$isArrowSet = 1;
    }

    # Draw objects
	my $isObjectSet = 0;
    foreach my $object (@{$self->{_objects}})
    {
        print PLT "set object"."$object\n";
		push(@sets, "object") if ($isObjectSet == 0);
		$isObjectSet = 1;
    }
    close(PLT);

    $self->_sets(\@sets);
}


# Set the details of the title
# - called by _setChart()
#
# Usage example:
# title => {
#     text   => "My title",
#     font   => "arial, 14",
#     color  => "brown",
#     offset => "0, -1",
# },
sub _setTitle
{
    my ($title) = @_;
    if (ref($title))
    {
        my $out = "\"$$title{text}\"";
        $out .= " offset $$title{offset}" if (defined $$title{offset});

        # Font and size
        my $font;
        $font = $$title{font} if (defined $$title{font});
        $font .= ",$$title{fontsize}" if (defined $$title{fontsize});
        $out .= " font \"$font\"" if (defined $font);

        # Color
        $out .= " textcolor rgb \"$$title{color}\"" if (defined $$title{color});

        # Switch of the enhanced mode. Default: off
        $out .= " noenhanced" if (!defined $$title{enhanced} ||
            $$title{enhanced} ne 'on');
        return($out);
    }
    else
    {
        return("\"$title\" noenhanced");
    }
}


# Set the details of the axis labels
# - called by _setChart()
#
# Usage example:
# xlabel => {
#     text   => "My x-axis label",
#     font   => "arial, 14",
#     color  => "brown",
#     offset => "0, -1",
#     rotate => 45,
# },
#
# TODO
# - support radian and pi in "rotate"
sub _setAxisLabel
{
    my ($label) = @_;
    if (ref($label))
    {
        my $out = "\"$$label{text}\"";

        # Location offset
        $out .= " offset $$label{offset}" if (defined $$label{offset});

        # Font and size
        my $font;
        $font = $$label{font} if (defined $$label{font});
        $font .= ",$$label{fontsize}" if (defined $$label{fontsize});
        $out .= " font \"$font\"" if (defined $font);

        # Color
        $out .= " textcolor rgb \"$$label{color}\"" if (defined $$label{color});

        # Switch of the enhanced mode. Default: off
        $out .= " noenhanced" if (!defined $$label{enhanced} ||
            $$label{enhanced} ne 'on');

        # Text rotation
        $out .= " rotate by $$label{rotate}" if (defined $$label{rotate});
        return($out);
    }
    else
    {
        return("\"$label\" noenhanced");
    }
}


# Set the details of the tics and tic labels
# - called by _setChart()
#
# Usage example:
# xtics => {
#    along     => 'border',
#    labels    => [-10, 15, 20, 25],
#    labelfmt  => "%3f",
#    font      => "arial",
#    fontsize  => 14,
#    fontcolor => "brown",
#    offset    => "0, -1",
#    start     => -10,
#    incr      => 0.2,
#    end       => 2.6,
#    rotate    => 45,
#    length    => "2,1",
#    along     => 'axis',
#    minor     => 3,
#    mirror    => 'off',
# },
#
# TODO
# - implement "add" option to add addition tics other than default
# - support radian and pi in "rotate"
sub _setTics
{
    my ($tic) = @_;

    my $out = '';
    if (ref($tic) eq 'HASH')
    {
        $out .= " $$tic{along}" if (defined $$tic{along});
        $out .= " nomirror" if (
            defined $$tic{mirror} && $$tic{mirror} eq 'off'
        );
        $out .= " scale $$tic{length}" if (defined $$tic{length});
        $out .= " rotate by $$tic{rotate}" if (defined $$tic{rotate});
        $out .= " offset $$tic{offset}" if (defined $$tic{offset});
		
		# Tic labels
		if (defined $$tic{incr})
		{
			my $location = $$tic{incr};
			if (defined $$tic{start})
			{
				$location = "$$tic{start},$location";
				$location .= ",$$tic{end}" if (defined $$tic{end});
			}

			$location = '0'.$location if ($location =~ /^\-/);
			$out .= " $location";
		}
        $out .= " (". join(',', @{$$tic{labels}}) . ")" if
            (defined $$tic{labels});

        # Font, font size and font color
        if (defined $$tic{font})
        {
            my $font = $$tic{font};
            $font = "$$tic{font},$$tic{fontsize}" if ($font !~ /\,/ &&
                defined $$tic{fontsize});
            $out .= " font \"$font\"";
        }
        $out .= " textcolor rgb \"$$tic{fontcolor}\"" if
            (defined $$tic{fontcolor});
    }
    elsif (ref($tic) eq 'ARRAY')
    {
        $out = " (". join(',', @$tic) . ")";
    }
    elsif ($tic ne 'on')
    {
        $out = "\"$tic\"";
    }
    return($out);
}


# Set the details of the grid lines
# - called by _setChart()
#
# Usage example:
# grid => {
#     type    => 'dash, dot',    # default: dot
#     width   => 2,              # default: 0
#     color   => 'blue',         # default: black
#     xlines  => 'on',           # default: on
#     ylines  => 'off',          # default: on
#     zlines  => 'off',          # default:
#     x2lines => 'off',          # default: off
#     y2lines => 'off',          # default: off
#     layer   => 'front',        # default: layerdefault
# },
#
# minorgrid => {
#     width   => 1,              # default: 0
#     color   => 'gray',         # default: black
#     xlines  => 'on',           # default: off
#     ylines  => 'on',           # default: off
#     x2lines => 'off',          # default: off
#     y2lines => 'off',          # default: off
#     layer   => 'front',        # default: layerdefault
# }
#
# # OR
# 
# grid => 'on',
#
# TODO:
# - support polar grid
sub _setGrid
{
    my ($self) = @_;
    my $grid = $self->{grid};
    my $mgrid = $self->{minorgrid} if (defined $self->{minorgrid});

    my $out = '';
    if (ref($grid) eq 'HASH' || ref($mgrid) eq 'HASH')
    {
        $grid = &_gridString2Hash($grid);
        $mgrid = &_gridString2Hash($mgrid);

        # Set whether the major grid lines are drawn
        (defined $$grid{xlines} && $$grid{xlines} =~ /^off/)?
            ($out .= " noxtics"): ($out .= " xtics");
        (defined $$grid{ylines} && $$grid{ylines} =~ /^off/)?
            ($out .= " noytics"): ($out .= " ytics");
        (defined $$grid{zlines} && $$grid{zlines} =~ /^off/)?
            ($out .= " noztics"): ($out .= " ztics");

        # Set whether the vertical minor grid lines are drawn
        $out .= " mxtics" if ( (defined $$grid{xlines} &&
            $$grid{xlines} =~ /,\s?on$/) ||
            (defined $self->{minorgrid} && (!defined $$mgrid{xlines} ||
            $$mgrid{xlines} eq 'on')) );

        # Set whether the horizontal minor grid lines are drawn
        $out .= " mytics" if ( (defined $$grid{ylines} &&
            $$grid{ylines} =~ /,\s?on$/) ||
            (defined $mgrid && (!defined $$mgrid{ylines} ||
            $$mgrid{ylines} eq 'on')) );

        # Major grid on secondary axes
        $out .= " x2tics" if (defined $$grid{x2lines} &&
            $$grid{x2lines} eq 'on');
        $out .= " y2tics" if (defined $$grid{y2lines} &&
            $$grid{y2lines} eq 'on');

        # Minor grid on secondary axes
        $out .= " mx2tics" if (defined $$mgrid{x2lines} &&
            $$mgrid{x2lines} eq 'on');
        $out .= " my2tics" if (defined $$mgrid{y2lines} &&
            $$mgrid{y2lines} eq 'on');

		# Set the layer
		$out .= " $$grid{layer}" if (defined $$grid{layer});

        # Set the line type of the grid lines
        my $major = my $minor = '';
        my $majorType = my $minorType = 4;  # dotted lines
        if (defined $$grid{linetype})
        {
            $majorType = $minorType = $$grid{linetype};
            ($majorType, $minorType) = split(/\,\s?/, $$grid{linetype}) if
                ($$grid{linetype} =~ /\,/);
        }
        $minorType = $$mgrid{linetype} if (defined $$mgrid{linetype});
        $major .= " linetype ".&_lineType($majorType);
        $minor .= " linetype ".&_lineType($minorType);
        
        # Set the line width of the grid lines
        my $majorWidth = my $minorWidth = 0;
        if (defined $$grid{width})
        {
            $majorWidth = $minorWidth = $$grid{width};
            ($majorWidth, $minorWidth) = split(/\,\s?/, $$grid{width}) if
                ($$grid{width} =~ /\,/);
        }
        $minorWidth = $$mgrid{width} if (defined $$mgrid{width});
        $major .= " linewidth $majorWidth";
        $minor .= " linewidth $minorWidth";

        # Set the line color of the grid lines
        my $majorColor = my $minorColor = 'black';
        if (defined $$grid{color})
        {
            $majorColor = $minorColor = $$grid{color};
            ($majorColor, $minorColor) = split(/\,\s?/, $$grid{color}) if
                ($$grid{color} =~ /\,/);
        }
        $minorColor = $$mgrid{color} if (defined $$mgrid{color});
        $major .= " linecolor rgb \"$majorColor\"";
        $minor .= " linecolor rgb \"$minorColor\"";
        $out .= "$major" if ($major ne '');
        $out .= ",$minor" if ($minor ne '');
    }
    else
    {
        if (defined $grid)
        {
            return(" $grid") if ($grid !~ /^(on|off)$/);
            ($grid eq 'off')? ($out = " noxtics noytics"):
                ($out = " xtics ytics");
        }
        $out .= " mxtics mytics" if (defined $mgrid && $mgrid eq 'on');
    }
    return($out);
}


# Convert grid string to hash
# - called by _setGrid
sub _gridString2Hash
{
    my ($grid) = @_;
    return($grid) if (ref($grid) eq 'HASH');

    my %out;
    $out{xlines} = $out{ylines} = $out{zlines} = $grid;
    return(\%out);
}


# Set the details of the graph border and legend box border
# - called by _setChart()
#
# Usage example:
# border => {
#      linetype => 3,            # default: solid
#      width    => 2,            # default: 0
#      color    => '#ff00ff',    # default: system defined
#      layer    => 'back',       # default: front
# },
#
# Remark:
# - By default, the color of the axis tics would follow the border unless
#   specified otherwise.
sub _setBorder
{
    my ($border) = @_;

    my $out = '';
	$out .= " $$border{layer}" if (defined $$border{layer});
    $out .= " linetype ".&_lineType($$border{linetype}) if
        (defined $$border{linetype});
    $out .= " linecolor rgb \"$$border{color}\"" if (defined $$border{color});
    $out .= " linewidth $$border{width}" if (defined $$border{width});
    return($out);
}


# Format the legend (key)
#
# Usage example:
# legend => {
#    position => "outside bottom",
#    width    => 3,
#    height   => 4,
#    align    => "right",
#    order    => "horizontal reverse",
#    title    => "Title of the legend",
#    sample   => {
#        length   => 3,
#        position => "left",
#        spacing  => 2,
#    },
#    border   => {
#        linetype => 2,
#        width    => 1,
#        color    => "blue",
#    },
# },
sub _setLegend
{
    my ($legend) = @_;

    my $out = '';
    if (defined $$legend{position})
    {
        ($$legend{position} =~ /\d/)? ($out .= " at $$legend{position}"):
            ($out .= " $$legend{position}");
    }
    $out .= " width $$legend{width}" if (defined $$legend{width});
    $out .= " height $$legend{height}" if (defined $$legend{height});
    if (defined $$legend{align})
    {
        $out .= " Left" if ($$legend{align} eq 'left');
        $out .= " Right" if ($$legend{align} eq 'right');
    }
    if (defined $$legend{order})
    {
        my $order = $$legend{order};
        $order =~ s/reverse/invert/;
        $out .= " $order";
    }
    if (defined $$legend{title})
    {
        if (ref($$legend{title}) eq 'HASH')
        {
            my $title = $$legend{title};
            $out .= " title \"$$title{text}\"";
            $out .= " noenhanced" if (!defined $$title{enhanced} ||
                $$title{enhanced} ne 'on');
        }
        else
        {
            $out .= " title \"$$legend{title}\" noenhanced";
        }
    }
    if (defined $$legend{sample})
    {
        $out .= " samplen $$legend{sample}{length}" if
            (defined $$legend{sample}{length});
        $out .= " reverse" if (defined $$legend{sample}{position} ||
            $$legend{sample}{position} eq "left");
        $out .= " spacing $$legend{sample}{spacing}" if
            (defined $$legend{sample}{spacing});
    }
    if (defined $$legend{border})
    {
        if (ref($$legend{border}) eq 'HASH')
        {
            $out .= " box ".&_setBorder($$legend{border});
        }
        elsif ($$legend{border} eq "off")
        {
            $out .= " no box";
        }
        elsif ($$legend{border} eq "on")
        {
            $out .= " box";
        }
    }
    return($out);
}


# Set title and layout of the multiplot
sub _setMultiplot
{
    my ($self, $nrows, $ncols) = @_;

    open(PLT, ">>$self->{_script}") || confess("Can't write $self->{_script}");
    print PLT "set multiplot";
    print PLT " title \"$self->{title}\"" if (defined $self->{title});
    print PLT " layout $nrows, $ncols" if (defined $nrows);
    print PLT "\n";
    close(PLT);
}


# Usage example:
# timestamp => {
#    fmt    => '%d/%m/%y %H:%M',
#    offset => "10,-3"
#    font   => "Helvetica",
# },
# # OR
# timestamp => 'on';
sub _setTimestamp
{
    my ($ts) = @_;

    my $out = '';
    if (ref($ts) eq 'HASH')
    {
        $out .= " \"$$ts{fmt}\"" if (defined $$ts{fmt});
        $out .= " offset $$ts{offset}" if (defined $$ts{offset});
        $out .= " font \"$$ts{font}\"" if (defined $$ts{font});
    }
    elsif ($ts ne 'on')
    {
        return($ts);
    }
    return($out);
}


# Call Gnuplot to generate the image file
sub execute
{
    my ($self) = @_;

    # Try to find the executable of Gnuplot
    my $gnuplot = 'gnuplot';
    if (defined $self->{gnuplot})
    {
        $gnuplot = $self->{gnuplot};
    }
    else
    {
        if ($^O =~ /MSWin/)
        {
            my $gnuplotDir = 'C:\Program Files\gnuplot';
            $gnuplotDir = 'C:\Program Files (x86)\gnuplot' if (!-e $gnuplotDir);

            my $binDir = $gnuplotDir.'\bin';
            $binDir = $gnuplotDir.'\binary' if (!-e $binDir);

            $gnuplot = $binDir.'\gnuplot.exe';
            if (!-e $gnuplot)
            {
                $gnuplot = $binDir.'\wgnuplot.exe';
                confess("Gnuplot command not found.") if (!-e $gnuplot);
            }
        }
    }

    # Execute gnuplot
    my $cmd = qq("$gnuplot" "$self->{_script}");
    $cmd .= " -" if ($self->{terminal} =~ /^(ggi|pm|windows|wxt|x11)(\s|$)/);
    my $err = `$cmd 2>&1`;
#    my $err;
#    system("$cmd");

    # Capture and process error message from Gnuplot
    if (defined $err && $err ne '')
    {
        my ($errTmp) = ($err =~ /\", line \d+:\s(.+)/);
        die "$errTmp\n" if (defined $errTmp);
        warn "$err\n";
    }

    # Convert the image to the user-specified format
    if (defined $self->{_terminal} && $self->{_terminal} eq 'auto')
    {
        my @a = split(/\./, $self->{output});
        my $ext = $a[-1];
        &convert($self, $ext) if ($ext !~ /^e?ps$/);
    }

    return($self);
}


# Unset the chart properties
# - called by multiplot()
sub _reset
{
    my ($self) = @_;
    open(PLT, ">>$self->{_script}") || confess("Can't write $self->{_script}");
    foreach my $opt (@{$self->{_sets}})
    {
        print PLT "unset $opt\n";

        if ($opt =~ /range$/)
        {
            print PLT "set $opt [*:*]\n";
        }
        elsif (!grep(/^$opt$/, qw(arrow grid label logscale object parametric))
			&& $opt !~ /tics$/)
        {
            print PLT "set $opt\n";
        }
    }
    close(PLT);
}


# Arbitrary labels placed in the chart
#
# Usage example:
# $chart->label(
#     text       => "This is a label",
#     position   => "0.2, 3 left",
#     offset     => "2,2",
#     rotate     => 45,
#     font       => "arial, 15",
#     fontcolor  => "dark-blue",
#     pointtype  => 3,
#     pointsize  => 5,
#     pointcolor => "blue",
#     layer      => "front",
# );
sub label
{
    my ($self, %label) = @_;

    my $out = " \"$label{text}\"";
    $out .= " at $label{position}" if (defined $label{position});
    $out .= " offset $label{offset}" if (defined $label{offset});
    $out .= " rotate by $label{rotate}" if (defined $label{rotate});
    $out .= " font \"$label{font}\"" if (defined $label{font});
	$out .= " $label{layer}" if (defined $label{layer});
    $out .= " textcolor rgb \"$label{fontcolor}\"" if
        (defined $label{fontcolor});
    $out .= " noenhanced" if (!defined $label{enhanced} ||
        $label{enhanced} ne 'on');

    if (defined $label{pointtype} || defined $label{pointsize} ||
        defined $label{pointcolor})
    {
        $out .= " point";
        $out .= " pointtype ".&_pointType($label{pointtype}) if
            (defined $label{pointtype});
        $out .= " pointsize $label{pointsize}" if (defined $label{pointsize});
        $out .= " linecolor rgb \"$label{pointcolor}\"" if
            (defined $label{pointcolor});
    }

    push(@{$self->{_labels}}, $out);
    return($self);
}


# Arbitrary arrows placed in the chart
#
# Usage example:
# $chart->arrow(
#     from     => "0,2",
#     to       => "0.3,0.1",
#     linetype => 'dash',
#     width    => 2,
#     color    => "dark-blue",
#     head     => {
#         size      => 3,
#         angle     => 30,
#         direction => 'back',
#     },
#     layer    => "front",
# );
sub arrow
{
    my ($self, %arrow) = @_;
    confess("Starting position of arrow not found") if (!defined $arrow{from});

    my $out = " from $arrow{from}";
    $out .= " to $arrow{to}" if (defined $arrow{to});
    $out .= " rto $arrow{rto}" if (defined $arrow{rto});
	$out .= " $arrow{layer}" if (defined $arrow{layer});
    $out .= " linetype ".&_lineType($arrow{linetype}) if
        (defined $arrow{linetype});
    $out .= " linewidth $arrow{width}" if (defined $arrow{width});
    $out .= " linecolor rgb \"$arrow{color}\"" if (defined $arrow{color});
    $out .= " size $arrow{headsize}" if (defined $arrow{headsize});

    # Set arrow head
    $out .= &_setArrowHead($arrow{head}) if (defined $arrow{head});

    push(@{$self->{_arrows}}, $out);
    return($self);
}


# Arbitrary lines placed in the chart
#
# Usage example:
# $chart->line(
#     from     => "0,2",
#     to       => "0.3,0.1",
#     linetype => 'dash',
#     width    => 2,
#     color    => "dark-blue",
#     layer    => "front",
# );
sub line
{
    my ($self, %line) = @_;
    confess("Starting position of line not found") if (!defined $line{from});

    my $out = " from $line{from}";
    $out .= " to $line{to}" if (defined $line{to});
    $out .= " rto $line{rto}" if (defined $line{rto});
	$out .= " $line{layer}" if (defined $line{layer});
    $out .= " linetype ".&_lineType($line{linetype}) if
        (defined $line{linetype});
    $out .= " linewidth $line{width}" if (defined $line{width});
    $out .= " linecolor rgb \"$line{color}\"" if (defined $line{color});

    push(@{$self->{_arrows}}, "$out nohead");    # remove arrow head
    return($self);
}


# Set the options of arrow head
sub _setArrowHead
{
    my ($head) = @_;
    my $out = '';

    # Author's comments:
    # - The filling of arrow head does not follow the convention of fill style
    #   of objects and plotting styles. Perhaps Gnuplot will change this in the
    #   future.
    # - Back-angle is not meaningful if filling is "nofilled". This constraint
    #   may be removed theoretically.
    # - Therefore, "backangle" and "fill" are disabled for the moment.
    if (ref($head) eq 'HASH')
    {
        my $size = (defined $$head{size})? $$head{size} : 0.45;
        my $angle = (defined $$head{angle})? $$head{angle} : 15;
        confess("arrow head size must be greater than 0") if ($size <= 0);

        $out .= " size $size";
        $out .= ",$angle" if ($size !~ /,/);
#        $out .= ",$$head{backangle}" if (defined $$head{backangle});
#        $out .= " $$head{fill}" if (defined $$head{fill});
        if (defined $$head{direction})
        {
            if ($$head{direction} eq 'back')
            {
                $out .= " backhead";
            }
            elsif ($$head{direction} eq 'both')
            {
                $out .= " heads";
            }
            elsif ($$head{direction} eq 'off')
            {
                $out .= " nohead";
            }
        }
    }
    else
    {
        if ($head eq 'off')
        {
            $out .= " nohead";
        }
        elsif ($head eq 'back')
        {
            $out .= " backhead";
        }
        elsif ($head eq 'both')
        {
            $out .= " heads";
        }
    }

    return($out);
}


# Arbitrary rectangles placed in the chart
#
# Usage example:
# $chart->rectangle(
#     from => "screen 0.2, screen 0.2",
#     to   => "screen 0.4, screen 0.4",
#     fill => {
#         density => 0.2,
#         color   => "#11ff11",
#     },
#     border => {color => "blue"},
# );
sub rectangle
{
    my ($self, %rect) = @_;

    # Position and dimension of the rectangle
    my $out = "";
    $out .= " $rect{index}" if (defined $rect{index});
    $out .= " rectangle";

    if (defined $rect{from})
    {
        $out .= " from $rect{from}";
        
        if (defined $rect{to})
        {
            $out .= " to $rect{to}";
        }
        elsif (defined $rect{rto})
        {
            $out .= " rto $rect{rto}";
        }
        else
        {
            confess("Rectangle dimension not complete");
        }
    }
    elsif (defined $rect{width})
    {
        $rect{at} = $rect{center} if (defined $rect{center});
        confess("Rectangle position not complete") if (!defined $rect{at});
        confess("Rectangle dimension not found") if (!defined $rect{width} ||
            !defined $rect{height});

        $out .= " at $rect{at} size $rect{width},$rect{height}";
    }
    else
    {
        confess("Rectangle position or dimension not complete");
    }

    # Process shared object options
    $out .= &_setObjOpt(\%rect);

    push(@{$self->{_objects}}, $out);
    return($self);
}


# Arbitrary ellipses placed in the chart
#
# Usage example:
# $chart->ellipse(
#     at     => "screen 0.2, screen 0.2",
#     width  => 0.2,
#     height => 0.5
#     fill   => {
#         density => 0.2,
#         color   => "#11ff11",
#     },
#     border => {color => "blue"},
# );
sub ellipse
{
    my ($self, %elli) = @_;

    # - Alias of "at": "center"
    # - Check position and dimension information
    $elli{at} = $elli{center} if (defined $elli{center});
    confess("Ellipse location not found") if (!defined $elli{at});
    confess("Ellipse dimension not found") if (!defined $elli{width} ||
        !defined $elli{height});

    my $out = "";
    $out .= " $elli{index}" if (defined $elli{index});
    $out .= " ellipse at $elli{at} size $elli{width},$elli{height}";
    $out .= " units $elli{units}" if (defined $elli{units});

    # Process shared object options
    $out .= &_setObjOpt(\%elli);

    push(@{$self->{_objects}}, $out);
    return($self);
}


# Arbitrary circles placed in the chart
#
# Usage example:
# $chart->circle(
#     at   => "screen 0.2, screen 0.2",
#     size => 0.5
#     fill => {
#         density => 0.2,
#         color   => "#11ff11",
#     },
#     border => {color => "blue"},
# );
sub circle
{
    my ($self, %cir) = @_;

    # - Alias of "at": "center"
    # - Check position and size information
    $cir{at} = $cir{center} if (defined $cir{center});
    confess("Circle location not found") if (!defined $cir{at});
    confess("Circle size not found") if (!defined $cir{size});

    my $out = "";
    $out .= " $cir{index}" if (defined $cir{index});
    $out .= " circle at $cir{at} size $cir{size}";

    if (defined $cir{arc})
    {
        (ref($cir{arc}) eq 'ARRAY')?
            ($out .= " arc [". join(':', @{$cir{arc}}) . "]"):
            ($out .= " arc [$cir{arc}]");
    }

    # Process shared object options
    $out .= &_setObjOpt(\%cir);

    push(@{$self->{_objects}}, $out);
    return($self);
}


# Arbitrary polygons placed in the chart
#
# Usage example:
# $chart->polygon(
#     vertices => [
#         "0, -0.6",
#         {rto => "-1, 0.3"},
#         {to => [-4, 0.4]},
#     ],
# );
sub polygon
{
    my ($self, %poly) = @_;
    confess("Polygon vertices not found") if (!defined $poly{vertices});

    my $v = $poly{vertices};
    confess("Polygon starting vertex not found") if (scalar(@$v) < 0.5);

    my $out = "";
    $out .= " $poly{index}" if (defined $poly{index});
    $out .= " polygon from $$v[0]";

    # Other vertices
    for (my $i = 1; $i < @$v; $i++)
    {
        if (ref($$v[$i]) eq 'HASH')
        {
            my @key = keys(%{$$v[$i]});
            my @val = values(%{$$v[$i]});
            $out .= " $key[0] $val[0]";
        }
        else
        {
            $out .= " to $$v[$i]";
        }
    }

    # Process shared object options
    $out .= &_setObjOpt(\%poly);

    push(@{$self->{_objects}}, $out);
    return($self);
}


# Set the details common to all objects
sub _setObjOpt
{
    my ($obj) = @_;
    my $out = "";
    $out .= " $$obj{layer}" if (defined $$obj{layer});
    $out .= " linewidth $$obj{linewidth}" if (defined $$obj{linewidth});

    # Set filling color / pattern and border
    if (defined $$obj{fill})
    {
        my $fill = $$obj{fill};
        $out .= " fillcolor rgb \"$$fill{color}\"" if (defined $$fill{color});
        $out .= " fillstyle". &_fillStyle($fill);

        # Set details of the border
        if (defined $$obj{border})
        {
            if (ref($$obj{border}) eq 'HASH')
            {
                $out .= " border";
                $out .= " linecolor rgb \"$$obj{border}{color}\"" if
                    (defined $$obj{border}{color});
            }
            elsif ($$obj{border} =~ /^(off|no)$/)
            {
                $out .= " noborder";
            }
        }
    }
    elsif (defined $$obj{border})
    {
        if (ref($$obj{border}) eq 'HASH')
        {
            $out .= " fillstyle border";
            $out .= " linecolor rgb \"$$obj{border}{color}\"" if
                (defined $$obj{border}{color});
        }
        elsif ($$obj{border} =~ /^(off|no)$/)
        {
            $out .= " noborder";
        }
    }
    return($out);
}


# Output a test image for the terminal
#
# Usage example:
# $chart = Chart::Gnuplot->new(output => "test.png");
# $chart->test;
sub test
{
    my ($self) = @_;

    my $pltTmp = "$self->{_script}";
    open(PLT, ">$pltTmp") || confess("Can't write gnuplot script $pltTmp");
    print PLT "set terminal $self->{terminal}\n";
    print PLT "set output \"$self->{output}\"\n";
    print PLT "test\n";
    close(PLT);

    # Execute gnuplot
    my $gnuplot = 'gnuplot';
    $gnuplot = $self->{gnuplot} if (defined $self->{gnuplot});
    system("$gnuplot $pltTmp");

    # Convert the image to the user-specified format
    if (defined $self->{_terminal} && $self->{_terminal} eq 'auto')
    {
        my @a = split(/\./, $self->{output});
        my $ext = $a[-1];
        &convert($self, $ext) if ($ext !~ /^e?ps$/);
    }
    return($self);
}


# Create animated gif
#
# Usage example:
# $chart->animate(
#     charts => \@charts,   # sequence of chart object
#     delay  => 10,         # delay in units of 0.01 second
# );
sub animate
{
    my ($self, %animate) = @_;
    my $charts = $animate{charts};

    # Force the terminal to be 'gif'
    # - Only the 'gif' terminal supports animation
    if (defined $self->{_terminal} && $self->{_terminal} eq 'auto')
    {
        $self->{terminal} = $self->{_terminal} = 'gif';
    }
    elsif ($self->{terminal} !~ /^gif/)
    {
        croak "animate() is supported only by the gif terminal";
    }
    $self->{terminal} .= " animate";
    $self->{terminal} .= " delay $animate{delay}" if (defined $animate{delay});

    &_setChart($self);

    open(PLT, ">>$self->{_script}") || confess("Can't write $self->{_script}");

    foreach my $chart (@$charts)
    {
        $chart->_script($self->{_script});
        $chart->_multiplot(1);

        my $plot;
        my @dataSet;
        if (defined $chart->{_dataSets2D})
        {
            $plot = 'plot';
            @dataSet = @{$chart->{_dataSets2D}};
        }
        elsif (defined $chart->{_dataSets3D})
        {
            $plot = 'splot';
            @dataSet = @{$chart->{_dataSets3D}};
        }
    
        &_setChart($chart, \@dataSet);
        open(PLT, ">>$self->{_script}") ||
            confess("Can't write $self->{_script}");
        print PLT "\n$plot ";
        print PLT join(', ', map {$_->_thaw($self)} @dataSet), "\n";
        close(PLT);
        &_reset($chart);
    }

    # Generate image file
    &execute($self);
    return($self);
}


# Change the image format
# - called by plot2d()
#
# Usage example:
# my $chart = Chart::Gnuplot->new(...);
# my $data = Chart::Gnuplot::DataSet->new(...);
# $chart->plot2d($data);
# $chart->convert('gif');
sub convert
{
    my ($self, $imgfmt) = @_;
    return($self) if (!-e $self->{output});

    # Generate temp file
    my $temp = "$self->{_script}.tmp";
    move($self->{output}, $temp);

    # Execute gnuplot
    my $convert = 'convert';
    $convert = $self->{convert} if (defined $self->{convert});

    # Rotate 90 deg for landscape image
    if (defined $self->{orient} && $self->{orient} eq 'portrait')
    {
        my $cmd = qq("$convert" $temp $temp.$imgfmt 2>&1);
        my $err = `$cmd`;
        if (defined $err && $err ne '')
        {
            die "Unsupported image format ($imgfmt)\n" if
                ($err =~ /^convert: unable to open module file/);

            my ($errTmp) = ($err =~ /^convert: (.+)/);
            die "$errTmp Perhaps the image format is not supported\n" if
                (defined $errTmp);
            die "$err\n";
        }
    }
    else
    {
        my $cmd = qq("$convert" -rotate 90 $temp $temp.$imgfmt 2>&1);
        my $err = `$cmd`;
        if (defined $err && $err ne '')
        {
            die "Unsupported image format ($imgfmt)\n" if
                ($err =~ /^convert: unable to open module file/);

            my ($errTmp) = ($err =~ /^convert: (.+)/);
            die "$errTmp Perhaps the image format is not supported\n" if
                (defined $errTmp);
            die "$err\n";
        }
    }

    # Remove the temp file
    move("$temp.$imgfmt", $self->{output});
    unlink($temp);
    return($self);
}


# Change the image format to PNG
#
# Usage example:
# my $chart = Chart::Gnuplot->new(...);
# my $data = Chart::Gnuplot::DataSet->new(...);
# $chart->plot2d($data)->png;
sub png
{
    my $self = shift;
    &convert($self, 'png');
    return($self)
}


# Change the image format to GIF
#
# Usage example:
# my $chart = Chart::Gnuplot->new(...);
# my $data = Chart::Gnuplot::DataSet->new(...);
# $chart->plot2d($data)->gif;
sub gif
{
    my $self = shift;
    &convert($self, 'gif');
    return($self)
}


# Change the image format to JPG
#
# Usage example:
# my $chart = Chart::Gnuplot->new(...);
# my $data = Chart::Gnuplot::DataSet->new(...);
# $chart->plot2d($data)->jpg;
sub jpg
{
    my $self = shift;
    &convert($self, 'jpg');
    return($self)
}


# Change the image format to PS
#
# Usage example:
# my $chart = Chart::Gnuplot->new(...);
# my $data = Chart::Gnuplot::DataSet->new(...);
# $chart->plot2d($data)->ps;
sub ps
{
    my $self = shift;
    &convert($self, 'ps');
    return($self)
}


# Change the image format to PDF
#
# Usage example:
# my $chart = Chart::Gnuplot->new(...);
# my $data = Chart::Gnuplot::DataSet->new(...);
# $chart->plot2d($data)->pdf;
sub pdf
{
    my $self = shift;
    &convert($self, 'pdf');
    return($self)
}


# Copy method of the chart object
sub copy
{
    my ($self, $num) = @_;
    my @clone = &_copy(@_);

    foreach my $clone (@clone)
    {
        my $dirTmp = tempdir(CLEANUP => 1);
        ($^O =~ /MSWin/)? ($dirTmp .= '\\'): ($dirTmp .= '/');
        $clone->{_script} = $dirTmp . "plot";
    }
    return($clone[0]) if (!defined $num);
    return(@clone);
}

################## Chart::Gnuplot::DataSet class ##################

package Chart::Gnuplot::DataSet;
use strict;
use Carp;
use File::Temp qw(tempdir);
use Chart::Gnuplot::Util qw(_lineType _pointType _fillStyle _copy);

# Constructor
sub new
{
    my ($class, %hash) = @_;

    my $dirTmp = tempdir(CLEANUP => 1);
    ($^O =~ /MSWin/)? ($dirTmp .= '\\'): ($dirTmp .= '/');
    $hash{_data} = $dirTmp . "data";

    my $self = \%hash;
    return bless($self, $class);
}


# Generic attribute methods
sub AUTOLOAD
{
    my ($self, $key) = @_;
    my $attr = our $AUTOLOAD;
    $attr =~ s/.*:://;
    return if ($attr eq 'DESTROY');        # ignore destructor
    $self->{$attr} = $key if (defined $key);
    return($self->{$attr});
}


# xdata get-set method
sub xdata
{
    my ($self, $xdata) = @_;
    return($self->{xdata}) if (!defined $xdata);

    delete $self->{points};
    delete $self->{datafile};
    delete $self->{func};
    $self->{xdata} = $xdata;
}


# ydata get-set method
sub ydata
{
    my ($self, $ydata) = @_;
    return($self->{ydata}) if (!defined $ydata);

    delete $self->{points};
    delete $self->{datafile};
    delete $self->{func};
    $self->{ydata} = $ydata;
}


# zdata get-set method
sub zdata
{
    my ($self, $zdata) = @_;
    return($self->{zdata}) if (!defined $zdata);

    delete $self->{points};
    delete $self->{datafile};
    delete $self->{func};
    $self->{zdata} = $zdata;
}


# points get-set method
sub points
{
    my ($self, $points) = @_;
    return($self->{points}) if (!defined $points);

    delete $self->{xdata};
    delete $self->{ydata};
    delete $self->{zdata};
    delete $self->{datafile};
    delete $self->{func};
    $self->{points} = $points;
}


# datafile get-set method
sub datafile
{
    my ($self, $datafile) = @_;
    return($self->{datafile}) if (!defined $datafile);

    delete $self->{xdata};
    delete $self->{ydata};
    delete $self->{zdata};
    delete $self->{points};
    delete $self->{func};
    $self->{datafile} = $datafile;
}


# func get-set method
sub func
{
    my ($self, $func) = @_;
    return($self->{func}) if (!defined $func);

    delete $self->{xdata};
    delete $self->{ydata};
    delete $self->{zdata};
    delete $self->{points};
    delete $self->{datafile};
    $self->{func} = $func;
}


# Copy method of the data set object
sub copy
{
    my ($self, $num) = @_;
    my @clone = &_copy(@_);

    foreach my $clone (@clone)
    {
        my $dirTmp = tempdir(CLEANUP => 1);
        ($^O =~ /MSWin/)? ($dirTmp .= '\\'): ($dirTmp .= '/');
        $clone->{_data} = $dirTmp . "data";
    }
    return($clone[0]) if (!defined $num);
    return(@clone);
}


# Thaw the data set object
# - call _fillStyle()
# _ call different _thaw*()
#
# TODO:
# - data file delimiter
# - data labels
sub _thaw
{
    my ($self, $chart) = @_;
    my $string;
    my $using = '';

    # Data points stored in arrays
    # - in any case, ydata need to be defined
    if (defined $self->{ydata})
    {
        my $fileTmp = $self->{_data};
        $string = "'$fileTmp'";

        # Process 3D data set
        # - zdata is defined
        if (defined $self->{zdata})
        {
            $using = (ref($self->{xdata}->[0]) eq 'ARRAY')?
                &_thawXYZGrid($self) : &_thawXYZ($self);
        }
        # Treatment for financebars and candlesticks styles
        # - Both xdata and ydata are defined
        elsif (defined $self->{xdata} && defined $self->{style} &&
            $self->{style} =~ /^(financebars|candlesticks)$/)
        {
            $using = &_thawXYFinance($self);
        }
        # Treatment for errorbars and errorlines styles
        # - Both xdata and ydata are defined
        # - Style is defined and contain "error"
        elsif (defined $self->{xdata} && defined $self->{style} &&
            $self->{style} =~ /error/)
        {
            # Error bars along x-axis
            if ($self->{style} =~ /^xerror/)
            {
                $using = &_thawXYXError($self);
            }
            # Error bars along y-axis
            elsif ($self->{style} =~ /^(y|box)error/)
            {
                $using = &_thawXYYError($self);
            }
            # Error bars along both x and y-axis
            elsif ($self->{style} =~ /^(box)?xyerror/)
            {
                $using = &_thawXYXYError($self);
            }
        }
        # Treatment for hbars
        # - use "boxxyerrorbars" style to mimic
        elsif (defined $self->{xdata} && defined $self->{style} &&
            $self->{style} eq 'hbars')
        {
            &_thawXYHbars($self);
        }
        # Treatment for hlines
        # - use "boxxyerrorbars" style to mimic
        elsif (defined $self->{xdata} && defined $self->{style} &&
            $self->{style} eq 'hlines')
        {
            &_thawXYHlines($self);
        }
        elsif (defined $self->{xdata} && defined $self->{style} &&
            $self->{style} eq 'histograms')
        {
            $using = &_thawXYHistograms($self);
        }
        # Normal x-y plot
        # - Both xdata and ydata are defined
        elsif (defined $self->{xdata})
        {
            $using = &_thawXY($self);
        }
        # Only ydata is defined
        # - Plot ydata against index
        else
        {
            # Treatment for financebars and candlesticks styles
            if (defined $self->{style} &&
                $self->{style} =~ /^(financebars|candlesticks)$/)
            {
                &_thawYFinance($self);
            }
            # Treatment for errorbars and errorlines styles
            # - Style is defined and contain "error"
            elsif (defined $self->{style} && $self->{style} =~ /^yerror/)
            {
                &_thawYError($self);
            }
            # Other plotting styles
            else
            {
                &_thawY($self);
            }
            $using = "1:2" if (defined $self->{timefmt});
        }
    }
    # Data in points
    elsif (defined $self->{points})
    {
        my $pt = $self->{points};
        my $fileTmp = $self->{_data};
        $string = "'$fileTmp'";

        # Horizontal lines plotting style
        if (defined $self->{style} && $self->{style} eq 'hlines')
        {
            &_thawPointsHLines($self);
        }
        # Horizontal bars plotting style
        elsif (defined $self->{style} && $self->{style} eq 'hbars')
        {
            &_thawPointsHBars($self);
        }
        # Horizontal bars plotting style
        elsif (defined $self->{style} && $self->{style} eq 'histograms')
        {
            $using = &_thawPointsHistograms($self);
        }
        # 3D grid data points
        elsif (ref($$pt[0][0]) eq 'ARRAY')
        {
            $using = &_thawPointsGrid($self);
        }
        else
        {
            $using = &_thawPoints($self);
        }
    }
    # File
    elsif (defined $self->{datafile})
    {
        $string = "'$self->{datafile}'";
        $string .= " every $self->{every}" if (defined $self->{every});
        $string .= " index $self->{index}" if (defined $self->{index});
    }
    # Function
    elsif (defined $self->{func})
    {
        # Parametric function
        if (ref($self->{func}) eq 'HASH')
        {
            if (defined ${$self->{func}}{z})
            {
                $string = "${$self->{func}}{x},${$self->{func}}{y},".
                    "${$self->{func}}{z}";
            }
            else
            {
                $string = "${$self->{func}}{x},${$self->{func}}{y}";
            }
        }
        else
        {
            $string = "$self->{func}";
        }
    }
    else
    {
        croak("Unknown or undefined data source");
    }

    # Process the Gnuplot "using" feature
    $using = $self->{using} if (defined $self->{using});
    $string .= " using $using" if ($using ne '');

    # Add title for the data sets
    (defined $self->{title})? ($string .= " title \"$self->{title}\""):
        ($string .= " title \"\"");

    # Change plotting style, color, width and point size
    $string .= " smooth $self->{smooth}" if (defined $self->{smooth});
    $string .= " axes $self->{axes}" if (defined $self->{axes});
    $string .= " with $self->{style}" if (defined $self->{style});
    $string .= " linetype ".&_lineType($self->{linetype}) if
        (defined $self->{linetype});
    $string .= " linecolor rgb \"$self->{color}\"" if (defined $self->{color});
    $string .= " linewidth $self->{width}" if (defined $self->{width});
    $string .= " pointtype ".&_pointType($self->{pointtype}) if
        (defined $self->{pointtype});
    $string .= " pointsize $self->{pointsize}" if (defined $self->{pointsize});
    
    # Filling style of the curve
    if (defined $self->{fill})
    {
        $string .= " fill".&_fillStyle($self->{fill});

        # Set details of the border
        if (defined $self->{border})
        {
            if (ref($self->{border}) eq 'HASH')
            {
                $string .= " border";
                $string .= " linecolor rgb \"$self->{border}{color}\"" if
                    (defined $self->{border}{color});
            }
            elsif ($self->{border} =~ /^(off|no)$/)
            {
                $string .= " noborder";
            }
        }
    }
    return($string);
}


# Process input data of array of y
sub _thawY
{
    my ($ds) = @_;
    my $ydata = $ds->{ydata};

    # Write data into temp file
    my $fileTmp = $ds->{_data};
    open(DATA, ">$fileTmp") || confess("Can't write data to temp file");
    for (my $i = 0; $i < @$ydata; $i++)
    {
        print DATA "$i $$ydata[$i]\n";
    }
    close(DATA);
}


# Process input data of array of y for plotting style "yerror..."
sub _thawYError
{
    my ($ds) = @_;
    my $ydata = $ds->{ydata};

    # Write data into temp file
    my $fileTmp = $ds->{_data};
    open(DATA, ">$fileTmp") || confess("Can't write data to temp file");
    for (my $i = 0; $i < @{$$ydata[0]}; $i++)
    {
        print DATA "$i $$ydata[0][$i]";
        for (my $j = 1; $j < @$ydata; $j++)
        {
            print DATA " $$ydata[$j][$i]";
        }
        print DATA "\n";
    }
    close(DATA);
}


# Process input data of array of y for plotting financial time series
sub _thawYFinance
{
    my ($ds) = @_;
    my $ydata = $ds->{ydata};

    # Write data into temp file
    my $fileTmp = $ds->{_data};
    open(DATA, ">$fileTmp") || confess("Can't write data to temp file");
    for (my $i = 0; $i < @{$$ydata[0]}; $i++)
    {
        print DATA "$i $$ydata[0][$i] $$ydata[1][$i] ".
            "$$ydata[2][$i] $$ydata[3][$i]\n";
    }
    close(DATA);
}


# Process input data of array of x and y
sub _thawXY
{
    my ($ds) = @_;

    my $xdata = $ds->{xdata};
    my $ydata = $ds->{ydata};
    croak("x-data and y-data have unequal length") if
        (scalar(@$ydata) != scalar(@$xdata));

    # Write data into temp file
    my $fileTmp = $ds->{_data};
    open(DATA, ">$fileTmp") || confess("Can't write data to temp file");
    for (my $i = 0; $i < @$xdata; $i++)
    {
        print DATA "$$xdata[$i] $$ydata[$i]\n";
    }
    close(DATA);

    # Construst using statement for date-time data
    my $using = '';
    if (defined $ds->{timefmt})
    {
        my @a = split(/\s+/, $$xdata[0]);
        my $yCol = scalar(@a) + 1;
        $using = "1:$yCol";
    }
    return($using);
}


# Process input data of array of x and y for plotting style "xerror..."
sub _thawXYXError
{
    my ($ds) = @_;

    my $xdata = $ds->{xdata};
    my $ydata = $ds->{ydata};
    croak("x-data and y-data have unequal length") if
        (scalar(@{$$xdata[0]}) != scalar(@$ydata));

    # Write data into temp file
    my $fileTmp = $ds->{_data};
    open(DATA, ">$fileTmp") || confess("Can't write data to temp file");
    for (my $i = 0; $i < @$ydata; $i++)
    {
        print DATA "$$xdata[0][$i] $$ydata[$i]";
        for (my $j = 1; $j < @$xdata; $j++)
        {
            print DATA " $$xdata[$j][$i]";
        }
        print DATA "\n";
    }
    close(DATA);

    # Construst using statement for date-time data
    my $using = '';
    if (defined $ds->{timefmt})
    {
        my ($xTmp) = (ref($$xdata[0]) eq 'ARRAY')? ($$xdata[0][0]):
            ($$xdata[0]);
        my @a = split(/\s+/, $xTmp);
        my $yCol = scalar(@a) + 1;
        $using = "1:$yCol";
    }
    return($using);
}


# Process input data of array of x and y for plotting style "yerror..."
sub _thawXYYError
{
    my ($ds) = @_;

    my $xdata = $ds->{xdata};
    my $ydata = $ds->{ydata};
    croak("x-data and y-data have unequal length") if
        (scalar(@{$$ydata[0]}) != scalar(@$xdata));

    # Write data into temp file
    my $fileTmp = $ds->{_data};
    open(DATA, ">$fileTmp") || confess("Can't write data to temp file");
    for (my $i = 0; $i < @$xdata; $i++)
    {
        print DATA "$$xdata[$i] $$ydata[0][$i]";
        for (my $j = 1; $j < @$ydata; $j++)
        {
            print DATA " $$ydata[$j][$i]";
        }
        print DATA "\n";
    }
    close(DATA);

    # Construst using statement for date-time data
    my $using = '';
    if (defined $ds->{timefmt})
    {
        my ($xTmp) = (ref($$xdata[0]) eq 'ARRAY')? ($$xdata[0][0]):
            ($$xdata[0]);
        my @a = split(/\s+/, $xTmp);
        my $yCol = scalar(@a) + 1;
        $using = "1:$yCol";
    }
    return($using);
}


# Process input data of array of x and y for plotting style "xyerror..."
sub _thawXYXYError
{
    my ($ds) = @_;

    my $xdata = $ds->{xdata};
    my $ydata = $ds->{ydata};

    # Write data into temp file
    my $fileTmp = $ds->{_data};
    open(DATA, ">$fileTmp") || confess("Can't write data to temp file");
    if (scalar(@$xdata) == scalar(@$ydata))
    {
        for (my $i = 0; $i < @{$$xdata[0]}; $i++)
        {
            print DATA "$$xdata[0][$i] $$ydata[0][$i]";
            for (my $j = 1; $j < @$ydata; $j++)
            {
                print DATA " $$xdata[$j][$i] $$ydata[$j][$i]";
            }
            print DATA "\n";
        }
    }
    else
    {
        for (my $i = 0; $i < @{$$xdata[0]}; $i++)
        {
            print DATA "$$xdata[0][$i] $$ydata[0][$i]";
            if (scalar(@$xdata) == 2)
            {
                my $ltmp = $$xdata[0][$i] - $$xdata[1][$i]*0.5;
                my $htmp = $$xdata[0][$i] + $$xdata[1][$i]*0.5;
                print DATA " $ltmp $htmp ".
                    "$$ydata[1][$i] $$ydata[2][$i]\n";
            }
            else
            {
                my $ltmp = $$ydata[0][$i] - $$ydata[1][$i]*0.5;
                my $htmp = $$ydata[0][$i] - $$ydata[1][$i]*0.5;
                print DATA " $$xdata[1][$i] $$xdata[2][$i] ".
                    "$ltmp $htmp\n";
            }
        }
    }
    close(DATA);
    
    # Construst using statement for date-time data
    my $using = '';
    if (defined $ds->{timefmt})
    {
        my ($xTmp) = (ref($$xdata[0]) eq 'ARRAY')? ($$xdata[0][0]):
            ($$xdata[0]);
        my @a = split(/\s+/, $xTmp);
        my $yCol = scalar(@a) + 1;
        $using = "1:$yCol";
    }
    return($using);
}


# Process input data of array of x and y for plotting financial time series
sub _thawXYFinance
{
    my ($ds) = @_;

    my $xdata = $ds->{xdata};
    my $ydata = $ds->{ydata};
    croak("x-data and y-data have unequal length") if
        (scalar(@{$$ydata[0]}) != scalar(@$xdata));

    # Write data into temp file
    my $fileTmp = $ds->{_data};
    open(DATA, ">$fileTmp") || confess("Can't write data to temp file");
    for (my $i = 0; $i < @$xdata; $i++)
    {
        print DATA "$$xdata[$i] $$ydata[0][$i] $$ydata[1][$i] ".
            "$$ydata[2][$i] $$ydata[3][$i]\n";
    }
    close(DATA);

    # Construst using statement for date-time data
    my $using = '';
    if (defined $ds->{timefmt})
    {
        my @a = split(/\s+/, $$xdata[0]);
        my $yCol = scalar(@a) + 1;
        $using = "1:".join(':', ($yCol .. $yCol+3));
    }
    return($using);
}


# Process input data of arrays of x and y for plottiny style "hlines"
sub _thawXYHlines
{
    my ($ds) = @_;
    my $xdata = $ds->{xdata};
    my $ydata = $ds->{ydata};

    # Write data into temp file
    my $fileTmp = $ds->{_data};
    open(DATA, ">$fileTmp") || confess("Can't write data to temp file");
    for (my $i = 0; $i < @$xdata; $i++)
    {
        print DATA "0 $$ydata[$i] 0 $$xdata[$i] $$ydata[$i] ".
            "$$ydata[$i]\n";
    }
    close(DATA);
    $ds->{style} = "boxxyerrorbars";
}


# Process input data of arrays of x and y for plottiny style "hbars"
sub _thawXYHbars
{
    my ($ds) = @_;
    my $xdata = $ds->{xdata};
    my $ydata = $ds->{ydata};

    # Put the corrdinates in a hash
    my %points;
    for (my $i = 0; $i < @$xdata; $i++)
    {
        $points{$$xdata[$i]} = $$ydata[$i];
    }

    # Sort x and y according to y values
    my (@sortX, @sortY) = ();
    foreach my $sx (sort {$points{$a} <=> $points{$b}} keys %points)
    {
        push(@sortX, $sx);
        push(@sortY, $points{$sx});
    }

    my $ylow = my $yhigh = $sortY[0];
    if (scalar(@sortY) > 1)
    {
        $ylow = 0.5*(3*$sortY[0]-$sortY[1]);
        $yhigh = 0.5*(3*$sortY[-1]-$sortY[-2]);
    }

    # Write data into temp file
    my $fileTmp = $ds->{_data};
    open(DATA, ">$fileTmp") || confess("Can't write data to temp file");
    for (my $i = 0; $i < @$xdata; $i++)
    {
        $ylow = 0.5*($sortY[$i]+$sortY[$i-1]) if ($i > 0);
        $yhigh = ($i < $#sortY)?
            0.5*($sortY[$i]+$sortY[$i+1]) :
            2.0*$sortY[$i] - $ylow;
        print DATA "0 $sortY[$i] 0 $sortX[$i] $ylow $yhigh\n";
    }
    close(DATA);
    $ds->{style} = "boxxyerrorbars";
}


# Process input data of arrays of x and y for plottiny style "histograms"
sub _thawXYHistograms
{
    my ($ds) = @_;
    my $xdata = $ds->{xdata};
    my $ydata = $ds->{ydata};
    croak("x-data and y-data have unequal length") if
        (scalar(@$ydata) != scalar(@$xdata));
    my $using;

    # Write data into temp file
    my $fileTmp = $ds->{_data};
    open(DATA, ">$fileTmp") || confess("Can't write data to temp file");
    if (ref($$ydata[0]) eq 'ARRAY')
    {
        for (my $i = 0; $i < @$xdata; $i++)
        {
            print DATA "\"$$xdata[$i]\" " . join(' ', @{$$ydata[$i]}) . "\n";
        }
        $using = join(':', (2 .. scalar(@{$$ydata[0]})+1)) . ":xticlabels(1)";
    }
    else
    {
        for (my $i = 0; $i < @$xdata; $i++)
        {
            print DATA "\"$$xdata[$i]\" $$ydata[$i]\n";
        }
        $using = "2:xticlabels(1)";
    }
    close(DATA);

    return($using);
}


# Process input data of array of x, y and z
sub _thawXYZ
{
    my ($ds) = @_;

    my $xdata = $ds->{xdata};
    my $ydata = $ds->{ydata};
    my $zdata = $ds->{zdata};
    croak("x-data and y-data have unequal length") if
        (scalar(@$ydata) != scalar(@$xdata));
    croak("y-data and z-data have unequal length") if
        (scalar(@$ydata) != scalar(@$zdata));

    # Write data into temp file
    my $fileTmp = $ds->{_data};
    open(DATA, ">$fileTmp") || confess("Can't write data to temp file");
    for (my $i = 0; $i < @$xdata; $i++)
    {
        print DATA "$$xdata[$i] $$ydata[$i] $$zdata[$i]\n";
    }
    close(DATA);

    # Construst using statement for date-time data
    my $using = '';
    if (defined $ds->{timefmt})
    {
        my @a = split(/\s+/, $$xdata[0]);
        my $yCol = scalar(@a) + 1;
        $using = "1:$yCol";

        my @b = split(/\s+/, $$ydata[0]);
        my $zCol = scalar(@b) + $yCol;
        $using .= ":$zCol";
    }
    return($using);
}


# Process input data of matrice of x, y and z
sub _thawXYZGrid
{
    my ($ds) = @_;

    my $xdata = $ds->{xdata};
    my $ydata = $ds->{ydata};
    my $zdata = $ds->{zdata};
    croak("x-data and y-data have unequal length") if
        (scalar(@$ydata) != scalar(@$xdata));
    croak("y-data and z-data have unequal length") if
        (scalar(@$ydata) != scalar(@$zdata));

    # Write data into temp file
    my $fileTmp = $ds->{_data};
    open(DATA, ">$fileTmp") || confess("Can't write data to temp file");
    for (my $i = 0; $i < @$xdata; $i++)
    {
        for (my $j = 0; $j < @{$$xdata[$i]}; $j++)
        {
            print DATA "$$xdata[$i][$j] $$ydata[$i][$j] $$zdata[$i][$j]\n";
        }
        print DATA "\n";
    }
    close(DATA);

    # Construst using statement for date-time data
    my $using = '';
    if (defined $ds->{timefmt})
    {
        my @a = split(/\s+/, $$xdata[0][0]);
        my $yCol = scalar(@a) + 1;
        $using = "1:$yCol";

        my @b = split(/\s+/, $$ydata[0][0]);
        my $zCol = scalar(@b) + $yCol;
        $using .= ":$zCol";
    }
    return($using);
}


# Process input data of array of points
sub _thawPoints
{
    my ($ds) = @_;

    # Write data into temp file
    my $pt = $ds->{points};
    my $fileTmp = $ds->{_data};
    open(DATA, ">$fileTmp") || confess("Can't write data to temp file");
    for (my $i = 0; $i < @$pt; $i++)
    {
        print DATA join(" ", @{$$pt[$i]}), "\n";
    }
    close(DATA);

    # Construst using statement for date-time data
    my $using = '';
    if (defined $ds->{timefmt})
    {
        my $col = 1;
        $using = "1";
        for (my $i = 0; $i < @{$$pt[0]}-1; $i++)
        {
            my @a = split(/\s+/, $$pt[0][$i]);
            $col += scalar(@a);
            $using .= ":$col";
        }
    }
    return($using);
}


# Process input data of array of points for plotting style "hlines"
sub _thawPointsHLines
{
    my ($ds) = @_;
    confess("Data/time input data is not supported in hlines plotting style")
        if (defined $ds->{timefmt});

    # Write data into temp file
    my $pt = $ds->{points};
    my $fileTmp = $ds->{_data};
    open(DATA, ">$fileTmp") || confess("Can't write data to temp file");

    # hlines plotting style
    for (my $i = 0; $i < @$pt; $i++)
    {
        print DATA "0 $$pt[$i][1] 0 $$pt[$i][0] $$pt[$i][1] $$pt[$i][1]\n";
    }

    $ds->{style} = "boxxyerrorbars";
    close(DATA);
}


# Process input data of array of points for plotting style "hbars"
sub _thawPointsHBars
{
    my ($ds) = @_;
    confess("Data/time input data is not supported in hbars plotting style")
        if (defined $ds->{timefmt});

    my $pt = $ds->{points};

    # Put the corrdinates in a hash
    my %points;
    for (my $i = 0; $i < @$pt; $i++)
    {
        $points{$$pt[$i][0]} = $$pt[$i][1];
    }

    # Sort x and y according to y values
    my (@sortX, @sortY) = ();
    foreach my $sx (sort {$points{$a} <=> $points{$b}} keys %points)
    {
        push(@sortX, $sx);
        push(@sortY, $points{$sx});
    }

    my $ylow = my $yhigh = $sortY[0];
    if (scalar(@sortY) > 1)
    {
        $ylow = 0.5*(3*$sortY[0]-$sortY[1]);
        $yhigh = 0.5*(3*$sortY[-1]-$sortY[-2]);
    }

    # Write data into temp file
    my $fileTmp = $ds->{_data};
    open(DATA, ">$fileTmp") || confess("Can't write data to temp file");
    for (my $i = 0; $i < @$pt; $i++)
    {
        $ylow = 0.5*($sortY[$i]+$sortY[$i-1]) if ($i > 0);
        $yhigh = ($i < $#sortY)?
            0.5*($sortY[$i]+$sortY[$i+1]) :
            2.0*$sortY[$i] - $ylow;
        print DATA "0 $sortY[$i] 0 $sortX[$i] $ylow $yhigh\n";
    }
    close(DATA);

    $ds->{style} = "boxxyerrorbars";
    close(DATA);
}


# Process input data of array of points for plotting histograms
sub _thawPointsHistograms
{
    my ($ds) = @_;

    # Write data into temp file
    my $pt = $ds->{points};
    my $fileTmp = $ds->{_data};
    open(DATA, ">$fileTmp") || confess("Can't write data to temp file");
    my $numCol = scalar(@{$$pt[0]});
    for (my $i = 0; $i < @$pt; $i++)
    {
        print DATA "\"$$pt[$i][0]\" ", join(' ', @{$$pt[$i]}[1 .. $numCol-1]),
            "\n";
    }
    close(DATA);

    my $using = join(':', (2 .. $numCol)) . ":xticlabels(1)";
    return($using);
}


# Process input data of a matrix of points
sub _thawPointsGrid
{
    my ($ds) = @_;

    # Write data into temp file
    my $pt = $ds->{points};
    my $fileTmp = $ds->{_data};
    open(DATA, ">$fileTmp") || confess("Can't write data to temp file");
    for (my $i = 0; $i < @$pt; $i++)
    {
        for (my $j = 0; $j < @{$$pt[$i]}; $j++)
        {
            print DATA join(" ", @{$$pt[$i][$j]}), "\n";
        }
        print DATA "\n";
    }
    close(DATA);

    # Construst using statement for date-time data
    my $using = '';
    if (defined $ds->{timefmt})
    {
        my $col = 1;
        $using = "1";
        for (my $i = 0; $i < @{$$pt[0][0]}-1; $i++)
        {
            my @a = split(/\s+/, $$pt[0][0][$i]);
            $col += scalar(@a);
            $using .= ":$col";
        }
    }
    return($using);
}


# Curve fitting method
#
# NOTICE: This feature is experimental and in alpha phase.
#
# Usage example:
# my $dataSet = Chart::Gnuplot::DataSet->new(...);
#
# my $dataFit = $dataSet->fit(
#    func => "a*x + b",                # linear fit
#    vars => 'x',
#    params => {a => -1, b => 0.5},    # seed
# );
#
# print "a = $dataFit->{params}->{a}\n";
# print "b = $dataFit->{params}->{b}\n";
#
# # Plot the raw data set and fitted curve
# $chart->plot2d($dataSet, $dataFit);
sub fit
{
    my ($self, %hash) = @_;
    my $script = my $data = my $result = my $log = $self->{_data};
    my $styleTmp = (defined $self->{style})? $self->{style} : 'lines';

    # Filename of the temp files
    $script =~ s/\/data$/\/fit\.script/;
    $result =~ s/\/data$/\/fit\.result/;
    $log =~ s/\/data$/\/fit\.log/;

    # Prepare parameter and error string for printing
    my $paraString = my $paraList = my $errList = '';
    my @params = ();
    my $paraRef = ref($hash{params});
    if ($paraRef eq 'HASH')
    {
        @params = keys %{$hash{params}};
        my @err = ();
        my $parFile = $self->{_data};
        $parFile =~ s/\/data$/\/par\.dat/;
        open(PARA, ">$parFile") || confess "Can't write parameter to $parFile";
        foreach my $pTmp (@params)
        {
            my $vTmp = (defined ${$hash{params}}{$pTmp})?
                ${$hash{params}}{$pTmp} : 1.0;
            print PARA "$pTmp = $vTmp\n";
            push(@err, $pTmp . "_err");
        }
        close(PARA);
        $paraString = "\"$parFile\"";
        $paraList = join(',', @params);
        $errList = join(',', @err);
    }
    elsif ($paraRef eq 'ARRAY')
    {
        @params = @{$hash{params}};
        my @err = map {$_ . '_err'} @params;
        $paraString = $paraList = join(',', @params);
        $errList = join(',', @err);
    }
    else
    {
        @params = split(/,\s*/, $hash{params});
        my @err = map {$_ . '_err'} @params;
        $paraString = $paraList = $hash{params};
        $errList = join(',', @err);
    }

    if (!defined $hash{using})
    {
        my @col = split(/\s*,\s*/, $hash{vars});
        my $numCol = scalar(@col) + 1;
        if (ref($self->{ydata}->[0]) eq 'ARRAY')
        {
            $numCol++;
            $self->{style} = 'yerror';    # temp style for data file generation
        }
        $hash{using} = join(':', (1 .. $numCol));
    }
    $self->_thaw() if (!-e $data);    # generate data file
    $self->{style} = $styleTmp;

    # Generate gnuplot script for curve fitting
    open(FIT, ">$script") || confess("Can't generate script to $script");
    print FIT "set fit logfile \"$log\" errorvariables\n";
    print FIT "set print \"$result\"\n";
    print FIT "fit $hash{func} \"$data\" using $hash{using}".
        " via $paraString\n";
    print FIT "print $paraList\n";
    print FIT "print $errList\n";
    close(FIT);

    # Call gnuplot
    system("gnuplot $script >& /dev/null");

    # Read and parse the result file
    open(RES, $result) || confess("Can't read fitting result $result");
    chomp(my ($pLine, $eLine) = <RES>);
    close(RES);

    # Save the result in DataSet object
    my %param;
    my @pVal = split(/\s+/, $pLine);
    my @eVal = split(/\s+/, $eLine);
    my $fitted = '';
    for (my $i = 0; $i < @pVal; $i++)
    {
        $param{$params[$i]} = $pVal[$i];
        $param{$params[$i]."_err"} = $eVal[$i];
        $fitted .= "$params[$i] = $pVal[$i],";
    }

    $fitted .= $hash{func};
    my $outDS = Chart::Gnuplot::DataSet->new(
        func   => $fitted,
        params => \%param,
    );
    return($outDS);
}


1;

__END__

#line 4076
