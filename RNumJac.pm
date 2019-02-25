package RNumJac;

# A stripped version of Matlab's numjac, an adaptive numerical Jacobian calculator for use by implicit ODE solvers, in particular those implemented in PerlGSL::DiffEq (See https://metacpan.org/pod/PerlGSL::DiffEq).

# Syntax: ($dFdy,$nfcalls) = numjac($F,$y,$Fy,$ythresh,$ytyp,\$fac);

# The algorithm is implemented in PDL.  $F is a function pointer.  All args after $F are vector pdls except $fac must be passed as a reference; their precise shape doesn't matter, but you can think of $y, $ythresh, $ytyp and $fac as row vectors of the same lenth, and $Fy as a column vector.  The elements of $y provide all the active arguments to $F.  Use a wrapper if $F requires additional parameters.  If you need time as an argument to $F, make it the first element of $y.  In that case the first column of the returned numerical derivatives pdl matrix$dFdy will contain the time derivatives of $F and the remaining columns will hold the usual jacobian.  Pass $Fy the values of $F($y) and defines the number of scalar functions comprising $F.  $dFdy has length($y) columns and length($Fy) rows.

# The helper vector $fac preserves values between calls, so that this routine can profit from recent experience. On the first call, pass the empty piddle $fac = zeros(0).  Make sure the values of $fac are preserved between subsequent calls. The strictly positive vector $ythresh provides a threshold of significance for y, i.e.  the exact value of a component y(i) with abs(y(i)) < ythresh(i) is not important. The vector $ytyp provides typical values of y.  Setting it to all zeros will cause it to have no effect, and will do no harm.

# This numjac() computes only full matrices (not sparse) and does not implement matlab "vectorization", but that ought not be a great loss since when we need an implicit solver, we are not likely to be working with a gradient of a potential, so Matlab's vectorization scheme would not come into play (?? is this really true??).See Matlab's numjac.m for a more complete discussion.

require Exporter;
@ISA	   = qw(Exporter);
@EXPORT    = qw(numjac);

use PDL;
use PDL::NiceSlice;
use PDL::Math;          # For isfinite, to detect nan.

use RPrint;

$VERSION='0.01';


#   Although NUMJAC was developed specifically for the approximation of partial derivatives when integrating a system of ODE's, it can be used for other applications.  In particular, when the length of the vector returned by F(T,Y) is different from the length of Y, DFDY is rectangular. 

#   NUMJAC is an implementation of an exceptionally robust scheme due to Salane for the approximation of partial derivatives when integrating  a system of ODEs, Y' = F(T,Y). It is called when the ODE code has an approximation Y at time T and is about to step to T+H.  The ODE code controls the error in Y to be less than the absolute error tolerance ATOL = THRESH.  Experience computing partial derivatives at previous steps is recorded in FAC.

#   D.E. Salane, "Adaptive Routines for Forming Jacobians Numerically", SAND86-1319, Sandia National Laboratories, 1986.

#   L.F. Shampine and M.W. Reichelt, The MATLAB ODE Suite, SIAM Journal on Scientific Computing, 18-1, 1997.

#   Mark W. Reichelt and Lawrence F. Shampine, 3-28-94 Copyright 1984-2006 The MathWorks, Inc. $Revision: 1.35.4.7 Date: 2006/02/21 20:43:34 $

use constant EPS => 2**(-52);
# In Matlab, eps returns the distance from 1.0 to the next larger double-precision number, that is, eps = 2^-52.
use constant BR         => EPS**(0.875);
use constant BL         => EPS**(0.75);
use constant BU         => EPS**(0.25);
use constant FACMIN     => EPS**(0.78);
use constant FACINIT    => EPS**(0.5);
use constant FACMAX     => 0.1;

my $verbose = 0;

sub numjac {
    my $nargs = @_;
    if ($nargs != 6){die "numjac: All 6 args must be passed.\n"}

    my ($F,$y,$Fy,$ythresh,$ytyp,$fac_ref) = @_;
    
    my $fac = ${$fac_ref};
    
    if ($verbose){print "\nIn numjac ...\n";pq($fac);pq($F,$y,$Fy,$ythresh,$ytyp,$fac)}
    #pqInfo($fac,$F,$y,$Fy,$ythresh,$ytyp,$fac);

    my $ny = $y->nelem;
    my $nF = $Fy->nelem;
    if ($fac->nelem == 0){
        #pq($fac);
        $fac = FACINIT*ones($ny);
    }
    
    # Note: thus fac(i) starts strictly positive.
    
    # Select an increment del for a difference approximation to column j of dFdy.  The vector fac accounts for experience gained in previous calls to numjac:
    
    # NOTE that yscale is strictly positive:
    my $yscale = abs($y);
    $yscale = MaxMerge($yscale,$ythresh);
    $yscale = MaxMerge($yscale,$ytyp);
    
        # Biggest of the choices, so ytyp = 0 has no effect, but thresh, which must be strictly positive, sets the lower bound.
    
    my $del = ($y + $fac*$yscale) - $y;
        ##  This must be about roundoff error.  In the next loop, fac is increased until either del becomes greater than zero or facmax is exceeded.  In the later case, del is simply set to thresh, a small user specified non-zero number.
    #pq($yscale,$del);
    
    # Make sure del is not zero, adjusting fac to that end, if possible:
    my $found = which($del == 0);
    foreach my $j ($found->list){
        while (1) {
            if ($fac($j)<FACMAX){
                #print "Changing fac A\n";
                $fac($j) .= MinMerge(100*$fac($j),FACMAX);
                $del($j) = ($y($j) + $fac($j)*$yscale($j)) - $y($j);
                if ($del($j)){last}
            }else{
                $del($j) = $ythresh($j);
                last;
            }
        }
    }
    
    # Make del positive:
    $del = abs($del);
    #pq($del);
    
    # Form a difference approximation to all columns of dFdy.  Because of the function call, there seems no advantage to doing some of these operations as matrices, rather than as vectors in a loop:
    my $ydel = $y->copy;
    my $dFdy        = zeros($ny,$nF);
    my $Difmax      = zeros($ny);
    my $Rowmax      = zeros($ny);
    my $absFdelRm   = zeros($ny);
    
    for (my $i=0;$i<$ny;$i++) {

        $ydel($i) += $del($i);

        my $Fdel = &$F($ydel);
        my $Fdiff = $Fdel-$Fy;
        $dFdy($i,:) .= ($Fdiff/$del($i))->transpose;
        #pq($i); pqf("%.18f ",$ydel,$y,$Fdel,$Fy,$Fdiff); print "\n";
        #pq($dFdy);      # So we can see its shape.
        
        my $absFdiff = abs($Fdiff);
        $Difmax($i) .= $absFdiff->max;
        $Rowmax($i) .= which($absFdiff==$Difmax($i))->index(0);
        $absFdelRm($i)  .= abs($Fdel)->index($Rowmax($i));

        $ydel($i) .= $y($i);    # This guarantees that there is no roundoff error in the restoration.
    }
    my $nfcalls = $ny;
    #print "after diff calc\n";pq($dFdy,$nfcalls);pq($Difmax,$Rowmax,$absFdelRm);print "\n";
    
    # Adjust fac for next call to numjac.
    my $absFy = abs($Fy);
    #pq($absFy);
    
    my $absFyRm = $absFy($Rowmax);
    
    #pq($absFdelRm,$absFyRm,$Difmax);
    my $jadj = (($absFdelRm != 0) * ($absFyRm != 0)) + ($Difmax == 0);
    #pq($jadj);
    #    my $jadj = (($absFdelRm != 0) and ($absFyRm != 0)) or ($Difmax == 0);
    if (any($jadj)){
        
        #print "In adjust ...\n";
        
        my $Fscale = MaxMerge($absFdelRm,$absFtyRm);   #??? careful with max if vectors happen to be scalars.
        #pq($Fscale);

        # If the difference in f values is so small that the column might be just roundoff error, try a bigger increment:
        my $k1 = ($Difmax <= BR*$Fscale);           # Difmax and Fscale might be zero
        #pq($k1);
        foreach my $k (which($jadj * $k1)->list){

            my $tmpfac = MinMerge(sqrt($fac($k)),FACMAX);
            my $delk = abs(($y($k) + $tmpfac*$yscale($k)) - $y($k));
            if ($tmpfac != $fac($k) and $delk != 0){
        
                $ydel($k) += $delk;         # Increment y(k).
                my $fdel = &$F($ydel);
                $nfcalls++;             # stats
                $ydel($k) .= $y($k);               # Restore y.

                my $fdiff       = $fdel-$Fy;
                my $tmpderiv    = $fdiff/$delk;   # Deriv

                my $absfdiff    = abs($fdiff);
                my $difmax      = $absfdiff->max;
                my $rowmax      = which($absfdiff==$difmax)->index(0);
  
                # MATLAB CODE:  if tmpfac * norm(tmp,inf) >= norm(dFdy(:,k),inf);  In matlab, dFdy(:,k) means the kth column of the matrix.
                ## IN LINEAR ALGEBRA, for vectors, the inf norm is just the max over i of |(i)|.  https://en.wikipedia.org/wiki/Norm_(mathematics)#p-norm

                if ($tmpfac * abs($tmpderiv)->max >= abs($dFdy($k,:))->max){
                # The new difference is more significant, so use the column computed with this increment.
                # norm(X,inf) means the max absolute row sum of the matrix, that is, ||X||=max(over i)(Sum over j of abs(aij)). but seems to require at least 2 columns. https://www.mathworks.com/help/matlab/ref/norm.html
                    $dFdy($k,:) .= $tmpderiv->transpose;
                    #pq($dFdy,$nfcalls);

                    # Adjust fac for the next call to numjac.
                    my $fscale = MaxMerge(abs($fdel($rowmax)),$absFy($rowmax));
                    
                    if ($difmax <= BL*$fscale){
                        # The difference is small, so increase the increment.
                       #print "Changing fac B\n";
                       $fac($k) .= MinMerge(10*$tmpfac,FACMAX);
                    }elsif ($difmax > BU*$fscale){
                        # The difference is large, so reduce the increment.
                        #print "Changing fac C\n";
                       $fac($k) .= MaxMerge(0.1*$tmpfac,FACMIN);
                    }else{
                        #print "Changing fac D\n";
                        $fac($k) .= $tmpfac;
                    }
                }
            }
        }
    
        # If the difference is small, increase the increment.
        my $k = which($jadj * !$k1 * ($Difmax <= BL*$Fscale));
        #pq($k);
        if (!$k->isempty){
            #print "Changing fac E\n";
            $fac($k) .= MinMerge(10*$fac($k),FACMAX)}

        # If the difference is large, reduce the increment.
        $k = which($jadj * ($Difmax > BU*$Fscale));
        #pq($k);
        if (!$k->isempty){
            #print "Changing fac F\n";
            $fac($k) .= MaxMerge(0.1*$fac($k),FACMIN)}
    }

    #pq($dFdy,$fac,$nfcalls);
    #pq($fac);print "... leaving numjac\n\n";
    
    ${$fac_ref} = $fac;

    return ($dFdy,$nfcalls);
}


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

1;

__END__
