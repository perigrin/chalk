my @r; for my $i (1..3) { my $x = {v => $i}; push @r, $x } print join(",", map { $_->{v} } @r), "\n";
