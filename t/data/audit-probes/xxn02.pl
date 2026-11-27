our $x = 1; sub chg { *x = \99 } chg(); print "$x\n";
