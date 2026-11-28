our $x = 1; our @x = (2); our @y = (5); *x = \@y; print "$x@x\n";
