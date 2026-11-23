our @g = (1,2); my @r; for my $i (1..2) { push @r, join(",", @g); $g[0] .= "x" } print "@r\n";
