my ($x,$y) = (1,2); for my $c (0,1) { for ($c ? $x : $y) { $_ *= 5 } } print "$x $y\n";
