my @r; my $x = 0; for my $i (1..3) { my $y = $x; $x = $i; push @r, \$y } print join(",", map { $$_ } @r), "\n";
