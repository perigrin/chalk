my @r; for my $i (1..3) { my @t=($i); push @r, \@t } print join(",", map { $_->[0] } @r), "\n";
