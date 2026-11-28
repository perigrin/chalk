my @c; my @a = (1,2,3); while (my ($e) = splice(@a, 0, 1)) { push @c, sub { $e } } print join(",", map { $_->() } @c), "\n";
