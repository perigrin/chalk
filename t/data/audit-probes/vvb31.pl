my @r; for my $i (1..3) { push @r, \my $x; $x = $i } print join(",", map { $$_ } @r), "\n";
