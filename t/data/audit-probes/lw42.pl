my @a = (3,1,2); my @r; for my $i (1..2) { push @r, join(",", @a); @a = sort { $a <=> $b } @a; push @a, 0 } print "@r\n";
