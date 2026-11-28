our ($x, $y, $z) = (1, 2, 3); *x = \$y; *y = \$z; $x = 5; $y = 6; print "$x$y$z\n";
