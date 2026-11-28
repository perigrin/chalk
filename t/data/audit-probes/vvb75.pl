my @c; my $i = 0; while (1) { my $x = $i++; last if $x > 2; push @c, sub { $x } } print join(",", map { $_->() } @c), "\n";
