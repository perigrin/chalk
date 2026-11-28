sub f { $_[0]++; 0 } my @t; for my $i (1..3) { my $y = $i; my $s = $y + f($y) + $y; push @t, $s } print "@t\n";
