our ($x, $y) = (1, 2); *x = \$y; *y = \$x; $x = 5; print "$x$y\n";
