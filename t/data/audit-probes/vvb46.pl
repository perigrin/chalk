our $i; my @r; for $i (1..3) { push @r, \$i } print join(",", map { $$_ } @r), "\n";
