my @c; for my $i (1..3) { my $x = $i; if ($i % 2) { push @c, sub { $x } } else { push @c, sub { -$x } } } print join(",", map { $_->() } @c), "\n";
