my ($x,$y,$z) = (1,2,3); my $k = 2; ($k == 1 ? $x : $k == 2 ? $y : $z) = 0; print "$x$y$z\n";
