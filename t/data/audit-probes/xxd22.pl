my @c; my $i; for $i (1..3) { push @c, sub { $i } } print join(",", map { defined($_->()) ? "d" : "u" } @c), "\n";
