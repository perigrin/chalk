my @c; for my $i (1..2) { my $x = $i * 10; for my $j (1..2) { push @c, sub { $x + $j } } } print join(",", map { $_->() } @c), "\n";
