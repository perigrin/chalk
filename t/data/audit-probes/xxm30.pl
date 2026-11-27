my @K; my $keep = sub { push @K, \$_[0] }; for my $i (1..3) { my $x = $i; $keep->($x) } print join(",", map { $$_ } @K), "\n";
