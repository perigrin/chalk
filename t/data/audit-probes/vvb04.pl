my @c; for (my $i = 0; $i < 3; $i++) { push @c, sub { $i } } print join(",", map { $_->() } @c), "\n";
