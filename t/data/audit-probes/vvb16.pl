my @c; for my $i (1..2) { my $x = $i * 10; for my $j (1..2) { $x++; push @c, sub { $x } } } print join(",", map { $_->() } @c), "\n";
