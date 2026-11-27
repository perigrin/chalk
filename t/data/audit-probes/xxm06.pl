my @r; for my $i (1..3) { my $q = \$i; push @r, $q } print join(",", map { $$_ } @r), "\n";
