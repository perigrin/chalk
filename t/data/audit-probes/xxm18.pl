my @r; for my $i (1..3) { my @x; push @x, $i; push @r, \@x } print join(",", map { scalar @$_ } @r), "\n";
