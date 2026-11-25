my @c; for my $i (0..2) { push @c, sub { $i } } print map({ $_->() } @c), "\n";
