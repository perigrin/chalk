my @r; for my $i (1..3) { my $x = $i; eval { push @r, \$x; die "z\n" }; } print join(",", map { $$_ } @r), "\n";
