my @r; for my $i (1..3) { my $q = \$i; $$q *= 2; push @r, $q } print join(",", map { $$_ } @r), "\n";
