my @c; for my $i (1..3) { push @c, sub { $i } } $_->() for @c; my @d; for my $i (4..5) { push @d, sub { $i } } print join(",", map { $_->() } @c, @d), "\n";
