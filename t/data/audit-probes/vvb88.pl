my @r; for my $i (1..3) { my $x = $i; my $r = \$x; push @r, $r; $x = $i * 2 } print join(",", map { $$_ } @r), "\n";
