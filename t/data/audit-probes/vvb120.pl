my @r; for my $i (1..3) { eval { my $x = $i; push @r, \$x; die "z\n" if $i == 2 }; } print join(",", map { $$_ } @r), "\n";
