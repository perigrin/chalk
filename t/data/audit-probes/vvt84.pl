sub f { $_[0]++; $_[0] } my @t; for my $i (1..3) { my $y = $i; push @t, f($y), $y } print "@t\n";
