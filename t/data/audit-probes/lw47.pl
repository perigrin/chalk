my @a = (1,2); my @r; for my $i (1..2) { for my $j (1..2) { push @r, join(",", @a) } for (@a) { $_ .= "x" } } print "@r\n";
