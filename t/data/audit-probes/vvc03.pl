our $x = 1; our $y = 2; *x = \$y; $y = 7; print "$x$y\n";
