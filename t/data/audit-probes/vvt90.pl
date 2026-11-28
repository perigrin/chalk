sub f { $_[0]++; 0 } my @t; for my $i (1..3) { push @t, $i, f($i), $i } print "@t\n";
