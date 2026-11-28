my @r; for my $i (1..3) { my $q = \$i; $$q *= 2; push @r, $i } print join(",", @r), "\n";
