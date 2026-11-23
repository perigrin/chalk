my @a = (1,2); my @r; for my $i (1..2) { if ($i) { push @r, join(",", @a) } for (@a) { $_ .= "x" } } print "@r\n";
