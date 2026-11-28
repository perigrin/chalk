my @r; for my $i (1..3) { my ($x, @y) = ($i, $i, $i); push @r, \@y } push @{$r[0]}, 9; print join(",", map { scalar @$_ } @r), "\n";
