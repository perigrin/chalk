my %h = (a=>1, b=>2); my @r; for my $i (1..2) { push @r, join(",", sort keys %h); delete $h{a} } print "@r\n";
