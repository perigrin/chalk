my @r; my $i = 0; do { my $j = $i++; push @r, \$j } while ($i < 3); print join(",", map { $$_ } @r), "\n";
