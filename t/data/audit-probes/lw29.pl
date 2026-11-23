my @a = (1,2); my @r; for my $i (1..2) { push @r, join(",", @a); @a = (@a, $i) } print "@r\n";
