my @r; for my $i (1..3) { my $x = $i; my $q = \$x; $x *= 2; $$q += 1; push @r, $x } print join(",", @r), "\n";
