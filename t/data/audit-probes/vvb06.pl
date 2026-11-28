my @c; for (my $i = 0; $i < 3; $i++) { my $j = $i; push @c, sub { $j } } print join(",", map { $_->() } @c), "\n";
