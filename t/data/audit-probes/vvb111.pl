my @c; for my $i (1..3) { push @c, sub { sub { $i } } } print join(",", map { $_->()->() } @c), "\n";
