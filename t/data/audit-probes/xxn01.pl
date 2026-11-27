our $x = 1; our $y = 2; sub chg { *x = \$y } chg(); $x = 5; print "$y\n";
