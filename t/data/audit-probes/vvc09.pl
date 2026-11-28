our @x = (1); our @y = (2,3); *x = \@y; push @x, 4; print "@x|@y\n";
