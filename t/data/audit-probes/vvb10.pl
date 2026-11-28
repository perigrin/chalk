my @r; my $i = 0; while ((my $j = $i++) < 3) { push @r, \$j } print join(",", map { $$_ } @r), "\n";
