my @r; for my $i (1..3) { my %x = (k => $i); push @r, \%x } print join(",", map { $_->{k} } @r), "\n";
