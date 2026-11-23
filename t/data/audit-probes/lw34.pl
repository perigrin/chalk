my @a = (1,2); my $p = \@a; my @r; for my $i (1..2) { push @r, join(",", @a); $p->[0] .= "x" } print "@r\n";
