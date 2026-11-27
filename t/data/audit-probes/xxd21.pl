my @c; my $i = 0; while ($i < 3) { my $j = $i; push @c, sub { $j }; $i++ } print join(",", map { $_->() } @c), "\n";
