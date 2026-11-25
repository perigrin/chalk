my @c; for my $i (1..3) { my $sq = $i * $i; push @c, sub { $sq + $_[0] } } print join(",", map { $_->(1) } @c), "\n";
