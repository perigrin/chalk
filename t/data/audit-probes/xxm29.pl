my $k = sub { \$_[0] }; my @r; for my $i (1..3) { my $x = $i; push @r, $k->($x) } print join(",", map { $$_ } @r), "\n";
