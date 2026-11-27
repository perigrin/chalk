my ($x,$y) = (1,2); for my $c (0,1,1) { ($c ? $x : $y) += 10 } print "$x $y\n";
