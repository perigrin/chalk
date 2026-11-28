my @r; for my $e (1,2,3) { push @r, \$e } print join(",", map { $$_ } @r), "\n";
