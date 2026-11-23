my %h = (a=>1); my @r; for my $i (1..2) { push @r, join(",", map { "$_=$h{$_}" } sort keys %h); %h = (%h, "k$i" => $i) } print "@r\n";
