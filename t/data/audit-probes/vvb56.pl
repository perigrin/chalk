my @c; for my $e (1,2,3) { push @c, sub { $e } } print join(",", map { $_->() } @c), "\n";
