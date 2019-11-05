package RUtils::LSFit;

## For smoothing jiggly data.  A replacement for PDL::Fit::Linfit (that doesn't need PDL::Slatec, which doesn't seem to be available).  In addition utility functions that give a least squares fit by lower order sines and cosines.  By Rich Miller 2019.

# Syntax:
#	($fit,$fits,$coeffs) = lsfit($ys,$fs);
#	($fit,$fits,$coeffs) = fourfit($xs,$ys,$order);
#	$fits = fourfitvals($coeffs,$xs);

use warnings;
use strict;
use POSIX ();
#require POSIX;
    # Require rather than use avoids the redefine warning when loading PDL.  But then I must always explicitly name the POSIX functions. See http://search.cpan.org/~nwclark/perl-5.8.5/ext/POSIX/POSIX.pod.  Implements a huge number of unixy (open ...) and mathy (floor ...) things.

#use Carp qw(carp croak confess cluck longmess shortmess);
use Carp;

use Exporter 'import';
our @EXPORT = qw( lsfit fourfit fourfitvals );

our $VERSION='0.01';

use PDL;
use PDL::AutoLoader;    # MATLAB-like autoloader.
use PDL::NiceSlice;
use PDL::LinearAlgebra;

use RUtils::Print;
use RUtils::Plot;

sub lsfit {
    my ($ys,$fs) = @_;
	
	## $ys is an m entry PDL row vector representing measured values at a number of locations $xs, $fs is an n row, m col PDL matrix whose rows represent the values of m fitting functions at the same locations.  Returns the coefficients that when multiplied by the fitting functions gives the vector whose difference with $ys is orthogonal to the fitting plane.
	
	## In fact, since msolve has this capability built in, $ys may be a PDL matrix having k rows.  In that case, on return $coeffs will also be a matrix with the same number of rows.  We are fitting a number of measured curves all with the same set of basis functions.
	
	my $fs_trans = $fs->transpose;

	my $Ys = $ys x $fs_trans;
	my $Hs = $fs x $fs_trans;
	
	#pq($Hs,$Ys);

	# Keep in mind that if msolve() doesn't work, you might try msolvex() which I believe has more stabilization:
	my $coeffs = msolve($Hs,$Ys->transpose)->transpose;
	#pq($coeffs);
	
	my $fits	= $coeffs x $fs;
	my $diffs	= $ys - $fits;
	my $fit		= sqrt(sumover($diffs**2));
	
	#pq($fit,$fits,$coeffs);

	return ($fit,$fits,$coeffs);
}

sub fourfit {
    my ($xs,$ys,$order) = @_;

    #print "\nEntering fourfit($xs,$ys,$order)\n";
	my $npts = $xs->nelem;
	
	if ($npts < 0 or $ys->dim(0) != $npts){croak "Error: \$xs and \$ys must be non-empty. \$xs must be a flat PDL, and \$ys a matrix with the same number of columns.\n"}
	
	if ($order < 0 or $order != floor($order)){croak "Error: \$order must be a non-negative integer.\n"}
	
	my $fs = zeros($npts,2*$order+1);
	
    for (my $ii=0;$ii<=$order;$ii++){
	
		if ($ii == 0){ $fs(:,$ii) .= ones($npts)}
		else {
			my $txs = $ii*$xs;
			$fs(:,2*$ii-1)	.= sin($txs);
			$fs(:,2*$ii)	.= cos($txs);
		}
    }

	#pq($xs,$ys,$order,$fs);
	
	my ($fit,$fits,$coeffs) = lsfit($ys,$fs);
	
	return ($fit,$fits,$coeffs);
}


sub fourfitvals {
    my ($coeffs,$xs) = @_;
	
	my $fits = $coeffs(0,:)*ones($xs);
	
	my $order = ($coeffs->dim(0)-1)/2;
	
    for (my $ii=1;$ii<=$order;$ii++){
	
		my $txs = $ii*$xs;
		$fits	+= $coeffs(2*$ii-1,:)*sin($txs);
		$fits	+= $coeffs(2*$ii,:)*cos($txs);
    }
	
	return $fits;
}


sub test {

	#my $xs = sequence(7)**2;
	my $xs = sequence(21)**2;
	$xs /= $xs(-1)->copy;
	
	my $ys = exp($xs);
	
	pq($xs,$ys);
	
	my $fs = ones($xs)->glue(1,$xs)->glue(1,$xs**2)->glue(1,$xs**3);
	
	my ($fit,$fits,$coeffs) = lsfit($ys,$fs);
	pq($fit,$fits,$coeffs);
	
    my %opts = (persist=>"persist");
	Plot($xs,$ys,"ys",$xs,$fits,"fits","lsfit test",\%opts);
	
	my $order = 3;
	($fit,$fits,$coeffs) = fourfit($xs,$ys,$order);
	pq($fit,$fits,$coeffs);

	Plot($xs,$ys,"ys",$xs,$fits,"fits","fourfit test",\%opts);
	
	my $xxs = sequence(100);
	$xxs /= $xxs(-1)->copy;
	
	my $yys = fourfitvals($coeffs,$xxs);
	
	Plot($xs,$ys,"ys",$xxs,$yys,"yys","fourfitvals test",\%opts);
	
	sleep(3);
	die;
}

#test();

return 1;

__END__

=head1 NAME

RUtils::FourFit - Least squares fit by lower order sines and cosines.

=head1 SYNOPSIS

use RUtils::LSFit;

	($fit,$fits,$coeffs) = lsfit($ys,$fs);
	($fit,$fits,$coeffs) = fourfit($xs,$ys,$order);
	$fits = fourfitvals($coeffs,$xs);

=head1 DESCRIPTION

For smoothing jiggly data.  A wrapper for PDL::Fit::Linfit that gives a least squares fit by lower order sines and cosines.  Rich Miller 2019.

=head2 EXPORT

lsfit fourfit fourfitvals

=head1 AUTHOR

Rich Miller, E<lt>rich@ski.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2019 by Rich Miller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.28.1 or,
at your option, any later version of Perl 5 you may have available.


=cut

