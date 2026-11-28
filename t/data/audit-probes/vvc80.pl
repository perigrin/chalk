our $x = 1; my $y = 5; *x = \$y; ($x, my $q) = (8, 9); print "$y\n";
