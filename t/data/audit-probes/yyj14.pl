my @c; for my $n (qw(a b)) { for my $m (1,2) { push @c, sub { "$n$m" } } } print join(",", map { $_->() } @c), "\n";
