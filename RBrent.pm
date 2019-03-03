package RBrent;

## From Numerical Recipes, p 268.

# Syntax:  ($x,$y) = rbrent($func,$x1,$x2,$tol,$iters,$arg0,$arg1,...);
#
#  The extra args are passed to func.

use warnings;
use strict;
use POSIX ();
#require POSIX;
    # Require rather than use avoids the redefine warning when loading PDL.  But then I must always explicitly name the POSIX functions. See http://search.cpan.org/~nwclark/perl-5.8.5/ext/POSIX/POSIX.pod.  Implements a huge number of unixy (open ...) and mathy (floor ...) things.

use RPrint;

use Exporter 'import';
our @EXPORT = qw( rbrent);

use PDL;
use PDL::AutoLoader;    # MATLAB-like autoloader.
use PDL::NiceSlice;

use constant EPS => 2**(-52);
# In Matlab, eps returns the distance from 1.0 to the next larger double-precision number, that is, eps = 2^-52.

# There doesn't seem much point in vectorizing this, since different input would correspond to different function parameters.  None the less, I was curious to see if I could do it.  Take this formulation as a joke.

# All the $argi's need to be singletons or vectors the same size as $x1, $x2.

sub rbrent {
    my ($func,$x1,$x2,$tol,$iters) = (shift,shift,shift,shift,shift);

    #print "\nEntering rbrent($x1,$x2,$tol,$iters,@_)\n";
    
    my $x0 = 69*ones($x1);  # The zeros to be returned.
    # So if not filled, something will scream at us.
    
    my $a = $x1->copy;
    my $b = $x2->copy;
    
    my ($tol1,$xm);
    my ($d,$e,$min1,$min2,$s,$p,$q,$r) = map {69*ones($x1)} (0..8);
    
    my $fa = &$func($a,@_);
    my $fb = &$func($b,@_);
    if (any($fa*$fb>0)){die "Error:  RBrent - Root must be bracketed.\n"}

    my $fc  = $fb->copy;
    my $c = $b->copy;       # Let's try this.

    my ($inds,$ok);
    for (my $iter=0;$iter<$iters;$iter++){
        
        #pq($iter);
        
        $inds = which($fb*$fc>0);
        if ($inds->nelem){              # Rename a,b,c, and adjust bounding interval d.
            $c($inds)   .= $a($inds);
            $fc($inds)  .= $fa($inds);
            
            ## Maybe the next two really wanted to be unindexed.
            $d($inds)   .= $b($inds)-$a($inds);
            $e($inds)   .= $d($inds);
        }
        
        $inds = which(abs($fc)<abs($fb));
        if ($inds->nelem){
            $a($inds) .= $b($inds);
            $b($inds) .= $c($inds);
            $c($inds) .= $a($inds);
            $fa($inds) .= $fb($inds);
            $fb($inds) .= $fc($inds);
            $fc($inds) .= $fa($inds);
        }
        
        $tol1   = 2*EPS*abs($b) + 0.5*$tol;     # Convergence check.
        $xm     = 0.5*($c-$b);
        
        #my $axm = abs($xm);
        ##my $xmtest = $axm<=$tol1;
        #my $fbtest = ($fb==0);
        #pq($axm,$tol1,$xmtest,$fbtest,$e);
        
        my ($keeperInds,$continueInds) = which_both((abs($xm)<=$tol1)+($fb==0));
        #pq($keeperInds,$continueInds,$b);print "\n";
        
        if ($keeperInds->nelem){
            # Take the successful indices out of the calculation.  Hold their return values.  Call rbrent reentrantly on those that are left:
            
            $x0($keeperInds) .= $b($keeperInds);
            #pq($x0);
            
            if ($continueInds->nelem){
                
                #pq($a,$b,$c,$fa,$fb,$fc);
                
                # Ok not to copy, done with originals.
                $a  = $a($continueInds);
                $b  = $b($continueInds);
                $c  = $c($continueInds);
                
                #pq($a,$b,$c);
                
                $ok = $a<$b;
                my $x1c = $ok*$a + (1-$ok)*$b;
                my $x2c = (1-$ok)*$a + $ok*$b;
                
                $ok = $c<$x1c;
                $x1c = $ok*$c + (1-$ok)*$x1c;
                
                $ok = $c>$x2c;
                $x2c = $ok*$c + (1-$ok)*$x2c;
                
                #pq($x1c,$x2c);
                
                
                my @argsCont;
                my $nCont = @_;
                for (my $j=0;$j<$nCont;$j++){
                    $argsCont[$j] = ($_[$j])->dice($continueInds)->copy;
                }
                #print "\nContinuing:\n";
                #pq($x1c,$x2c,$tol,$iters);print "argsCont=@argsCont\n";
                
                my $x0Continue = rbrent($func,$x1c,$x2c,$tol,$iters,@argsCont);
                #pq($x0Continue,$continueInds);
                
                $x0($continueInds) .= $x0Continue;
            }
            return $x0;
        }
        
        my ($YInds,$NInds);
        my ($yInds,$nInds);
        my $i;

        ($YInds,$NInds) = which_both((abs($e)>=$tol1)*(abs($fa)>=abs($fb)));
        #print "quad choice:  ";pq($YInds,$NInds);
        
        if ($YInds->nelem){             # Attempt inverse quadratic interpolation
            
            #print "doing quad\n";pq($e,$d);
            
            $s($YInds) .= $fb($YInds)/$fa($YInds);

            ($yInds,$nInds) = which_both($a($YInds)==$c($YInds));
            if ($yInds->nelem){
                #print "YYY\n";
                $i = $YInds($yInds);
                $p($i) .= 2*$xm($i)*$s($i);
                $q($i) .= 1-$s($i);
                #pq($p,$q);
            }
            if ($nInds->nelem){
                #print "NNN\n";
                $i = $YInds($nInds);
                $q($i) .= $fa($i)/$fc($i);
                $r($i) .= $fb($i)/$fc($i);
                $p($i) .= $s($i)*( 2*$xm($i)*$q($i)*($q($i)-$r($i))
                                    - ($b($i)-$a($i))*($r($i)-1) );
                $q($i) .= ($q($i)-1)*($r($i)-1)*($s($i)-1);
            }
        
            #print "before check ";pq($p);
            $i = which($p($YInds)>0);       # Check whether in bounds
            if ($i->nelem){$q($YInds($i)) .= -$q($YInds($i))}
            #print "after check ";pq($q);
            
            $p($YInds)      .= abs($p($YInds));
            $min1($YInds)   .= 3*$xm($YInds)*$q($YInds) - abs($tol1($YInds)*$q($YInds));
            $min2($YInds)   .= abs($e($YInds)*$q($YInds));
            #print "after mins ";pq($p,$q,$min1,$min2);
            
            $ok = $min1($YInds)<$min2($YInds);
            my $min = $min1($YInds)*$ok + $min2($YInds)*(1-$ok);
            #pq($min);
            ($yInds,$nInds) = which_both(2*$p($YInds)<$min);
            if ($yInds->nelem){             # Accept interpolation
               # print "interp was ok\n";
                $i = $YInds($yInds);
                $e($i) .= $d($i);
                $d($i) .= $p($i)/$q($i);
                #pq($e,$d);print "\n";
            }
            if ($nInds->nelem){             # Interpolation failed, use bisection
                #print "interp failed, use bisection\n";
                $i = $YInds($nInds);
                $d($i) .= $xm($i);
                $e($i) .= $d($i);
                #pq($e,$d);print "\n";
            }
        }
        if ($NInds->nelem){
            #print "Just updating d,e\n";
            $d($NInds) .= $xm($NInds);
            $e($NInds) .= $d($NInds);
            #pq($e,$d);print "\n";
        }
        
        $a  .= $b;                       # Move last best guess to a
        $fa .= $fb;
        
        ($YInds,$NInds) = which_both(abs($d)>=$tol1);
        if ($YInds->nelem){             # Evaluate new trial root
            #print "Eval new root YYY\n";
            #pq($b);
            $b($YInds) += $d($YInds);
            #pq($b);
        }
        if ($NInds->nelem){
            #print "Eval new root NNN\n";
            #            $b($NInds) += ??($xm($NInds)>0)?abs($tol1($NInds)):-abs($tol1($NInds));
            
            my $sign = $xm($NInds)>0;
            $sign = 2*$sign-1;
            #pq($sign,$b);
            $b($NInds) += $sign*abs($tol1($NInds));
            #pq($b);
        }
        
        $fb = &$func($b,@_);        # Get new function value
        #pq($fb);
        
    } # End iter
    
    die "RBrent:  MAXIMUM number of function evaluation exceeded\n";
}


return 1;
