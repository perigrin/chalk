our $x = 1; sub chg { *x = \99 } my $o = $x; chg(); my $n = $x; print "$o$n\n";
