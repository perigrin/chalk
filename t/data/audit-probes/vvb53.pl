my @a = (1,2,3); my @c; for my $e (@a) { push @c, sub { $e } } $a[0] = 9; print join(",", map { $_->() } @c), "\n";
