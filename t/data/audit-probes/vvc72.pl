our $x = 1; my ($y, $z) = (5, 6); for my $r (\$y, \$z) { *x = $r; $x++ } print "$y$z\n";
