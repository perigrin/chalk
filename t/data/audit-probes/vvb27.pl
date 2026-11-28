my @r; for my $i (1..3) { my %h = (k => $i); push @r, \%h } print join(",", map { $_->{k} } @r), "\n";
