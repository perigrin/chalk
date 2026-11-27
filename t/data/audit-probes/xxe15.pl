our $x = 1; sub chg { *x = \99 } my $o = $x; chg(); print "$o$x\n";
