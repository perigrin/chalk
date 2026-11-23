my @a = (1,2,3); my @r; for my $i (1..2) { push @r, join(",", @a); splice(@a, 0, 1, "s$i") } print "@r\n";
