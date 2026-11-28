my @c; for (1..3) { my $v = $_; push @c, sub { $v } } print join(",", map { $_->() } @c), "\n";
