my @r; for my $i (1..3) { my $x = [$i]; push @r, $x } $r[0][0] = 9; print join(",", map { $_->[0] } @r), "\n";
