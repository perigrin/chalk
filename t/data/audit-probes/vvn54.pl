my @r; for my $i (1..3) { $r[$i] = \$i } print join(",", map { $$_ } @r[1..3]), "\n";
