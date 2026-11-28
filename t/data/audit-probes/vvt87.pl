sub f { $_[0]++; 0 } my @t; for my $i (1..3) { my $y = $i; push @t, "$y" . f($y) . "$y" } print "@t\n";
