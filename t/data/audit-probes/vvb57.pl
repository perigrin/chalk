my ($p, $q) = (1, 2); my @c; for my $e ($p, $q) { push @c, sub { $e } } $p = 7; print join(",", map { $_->() } @c), "\n";
