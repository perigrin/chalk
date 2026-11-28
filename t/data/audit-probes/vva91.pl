our $x = 1; our $y = 2; { local *x = *y; $x = 5 } print "$x$y\n";
