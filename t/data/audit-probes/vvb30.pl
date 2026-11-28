my @r; for my $i (1..3) { my %h; $h{$i} = 1; push @r, join("", sort keys %h) } print join(",", @r), "\n";
