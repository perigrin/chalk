my @r; for my $i (1..3) { my @x = ($i); push @r, \@x } print join(",", map { $_->[0] } @r), "\n";
