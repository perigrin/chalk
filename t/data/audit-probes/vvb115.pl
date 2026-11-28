my @c; my @a = (1,2,3); while (my $e = shift @a) { push @c, sub { $e } } print join(",", map { $_->() } @c), "\n";
