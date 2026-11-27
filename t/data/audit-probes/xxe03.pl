our @x = (1); our @y = (2); *x = \@y; push @x, 3; print "@y\n";
