my @c; my $i = 0; while ((my $j = $i++) < 3) { push @c, sub { $j } } print join(",", map { $_->() } @c), "\n";
