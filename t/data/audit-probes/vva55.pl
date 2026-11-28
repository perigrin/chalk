our ($x, $y) = (1, 2); { local $x = $y; local $y = $x; print "$x$y" } print "$x$y\n";
