my @c = map { my $x = $_; sub { $x } } 1..3; print join(",", map { $_->() } @c), "\n";
