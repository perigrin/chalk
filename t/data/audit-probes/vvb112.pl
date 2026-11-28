my @c; for my $i (1..2) { my @in; for my $j (1..2) { push @in, sub { $i * $j } } push @c, \@in } print join(",", map { map { $_->() } @$_ } @c), "\n";
