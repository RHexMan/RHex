#!/usr/bin/perl

#############################################################################
## Name:			RPrint
## Purpose:			Quick print functions
## Author:			Rich Miller
## Modified by:
## Created:			2017/10/27
## Modified:		2017/10/27
## RCS-ID:
## Copyright:		(c) 2017 Rich Miller
## License:			This program is free software; you can redistribute it and/or
##					modify it under the same terms as Perl itself
#############################################################################

# syntax:  use RPrint;

package RPrint;

use Carp;

use Exporter 'import';
our @EXPORT = qw( pq pqf pqInfo);

use warnings;
use strict;

use PDL;
# Import main PDL module (see PDL.pm for equivalents).  In particular, imports PDL::Math, which redefines many POSIX math functions.  To get the original, call POSIX::aFunction.
use PDL::NiceSlice;

#use Try::Tiny;

use PadWalker qw(peek_my);
#use Scalar::Util 'refaddr';
use Scalar::Util qw(refaddr looks_like_number);
use Data::Dump qw(dump);    # for testing


sub pq {
    
    ## Print named output from perl variable types plus pdl.  To streamline debugging print statements.  Adapted from Data::Dumper::Names
    
    ## Works fine on perl scalars and pdls.  When a perl array is passed, the flattening messes things up.  Ditto a hash.  The cure is to call this function with references to arrays and hashes (\@goo,\%blop).
    
    my $upLevel = 1;
    my $pad = peek_my($upLevel);

#print "dumping \$pad\n";
#print dump($pad);
#print "\n...done\n";

    my %pad_vars;
    while ( my ( $var, $ref ) = each %$pad ) {

    
#print "AA: var=$var, ref=$ref\n";

        # we no longer remove the '$' sigil because we don't want
        # "$foo = \@array" reported as "@foo".
#        $var =~ s/^[\@\%]/*/;
        $pad_vars{ refaddr $ref } = $var;
# refaddr:  If $ref is reference the internal memory address of the referenced value is returned as a plain integer. Otherwise undef is returned.

    }
#print "dumping \%pad_vars\n";
#print dump(%pad_vars);
#print "\n...done\n";

    my @names;
    my $varcount = 1;
    foreach (@_) {
#print "BB=$_\n";    # Rich
        my $name = "";
        INNER: foreach ( \$_, $_ ) {
            no warnings 'uninitialized';
            $name = $pad_vars{ refaddr $_} and last INNER;
        }
        if ($name eq ""){carp "WARNING: pq - DOES NOT WORK ON IMPORTED VARIABLES.  Arrays and hashes must be passed by reference (\\\@foo,\\\%goo).\n";return}
#print "NAME=$name\n";
        my $sigil = substr($name,0,1);
#print "SIGIL=$sigil\n";
        if ($sigil eq '@' or $sigil eq '%') {
            my $dstr = dump($_);
            print "$name = $dstr\n";
        } else {
            print "$name = $_\n";
        }
#print "\n";
    }
}

sub pqf {
    my $format = shift;
    
    ## Print named output from perl variable types plus pdl.  To streamline debugging print statements.  Adapted from Data::Dumper::Names.  Arrays or hashes must be passed as refs (\@xxx, \%yyy).
    
    my $upLevel = 1;
    my $pad = peek_my($upLevel);
    
    my %pad_vars;
    while ( my ( $var, $ref ) = each %$pad ) {
        
        # we no longer remove the '$' sigil because we don't want
        # "$foo = \@array" reported as "@foo".
        #        $var =~ s/^[\@\%]/*/;
        $pad_vars{ refaddr $ref } = $var;
        # refaddr:  If $ref is reference the internal memory address of the referenced value is returned as a plain integer. Otherwise undef is returned.
        
    }
    
    my @names;
    my $varcount = 1;
    foreach (@_) {
        my $name = "";
    INNER: foreach ( \$_, $_ ) {
        no warnings 'uninitialized';
        $name = $pad_vars{ refaddr $_} and last INNER;
    }
        if ($name eq ""){carp "WARNING: pq - DOES NOT WORK ON IMPORTED VARIABLES.  Arrays and hashes must be passed by reference (\\\@foo,\\\%goo).\n";return}

        my $sigil = substr($name,0,1);
        if ($sigil eq '%') {
            carp "WARNING: pqf - Not implemented for hashes.\n"; return;
        } elsif ($sigil eq '@') {
#print "Array --- $_\n";
            my @tArray = @$_;
#print "tArray=@tArray\n";
            my $ss=""; foreach my $ff (@$_){
#print "ff=$ff\n";
                $ss .= sprintf($format,$ff);
            }
            print "$name = ";
            print "$ss\n";
        } else {    # check if it is a pdl
            my $ss=""; foreach my $ff ($_->list){
                $ss .= sprintf($format,$ff);
            }
            print "$name = ";
            print "$ss\n";
        }
    }
}

sub pqInfo {  # There has to be a better way.
    
    ## Print info for named pdl. To streamline debugging print statements.  Adapted from Data::Dumper::Names.
    my $upLevel = 1;
    my $pad = peek_my($upLevel);
    
    my %pad_vars;
    while ( my ( $var, $ref ) = each %$pad ) {
        
        $pad_vars{ refaddr $ref } = $var;
        # refaddr:  If $ref is reference the internal memory address of the referenced value is returned as a plain integer. Otherwise undef is returned.
    }
    
    my @names;
    my $varcount = 1;
    foreach (@_) {
        my $name;
    INNER: foreach ( \$_, $_ ) {
        no warnings 'uninitialized';
        $name = $pad_vars{ refaddr $_} and last INNER;
    }
        if (ref($_) eq 'PDL'){
            my $str = $_->info("Type: %T Dim: %-15D State: %S Mem: %M\n");
            print "$name -- INFO -- $str\n";
        }else{
            carp "WARNING: pqInfo only implemented for pdls.\n";
        }
    }
}

# Required package return value:
1;
