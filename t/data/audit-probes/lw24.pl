my %h = (a=>1, b=>2); my @r; for my $i (1..2) { push @r, join(",", map { "$_=$h{$_}" } sort keys %h); @h{qw(a b)} = ($i, $i) } print "@r\n";
