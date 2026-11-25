my @r; my $i=0; while ($i < 3) { my %t=(v=>$i); push @r, \%t; $i++ } print join(",", map { $_->{v} } @r), "\n";
