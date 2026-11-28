my @c; my $x; for my $i (1..3) { $x = $i; push @c, sub { $x } } print join(",", map { $_->() } @c), "\n";
