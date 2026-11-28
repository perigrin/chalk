my ($lo, $hi) = (1, 3); my @c; for my $i ($lo..$hi) { push @c, sub { $i } } $hi = 9; print join(",", map { $_->() } @c), "\n";
