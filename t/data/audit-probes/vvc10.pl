our @x = (1); my @y = (2,3); *x = \@y; $x[0] = 9; print "@x|@y\n";
