my @c; for my $i (1..3) { my $x = $i; push @c, sub { my $y = $x; sub { $y + $x } } } $_ = $_->() for @c; print join(",", map { $_->() } @c), "\n";
