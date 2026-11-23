my %h = (a=>1); my $p = \%h; my @r; for my $i (1..2) { push @r, join(",", map { "$_=$h{$_}" } sort keys %h); $p->{"k$i"} = $i } print "@r\n";
