my @a = (1,2); my @r; for my $i (1..2) { push @r, join(",", @a); my $p = \@a; $p->[0] .= "x" } print "@r\n";
