my @c; my $i = 0; while ($i < 3) { my $x = $i; $i++; next if $x == 1; push @c, sub { $x } } print join(",", map { $_->() } @c), "\n";
