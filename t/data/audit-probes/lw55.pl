my @a = (1,2); my @r; for my $i (1..2) { push @r, join(",", @a); if ($i) { for (@a) { $_ .= "x" } } } print "@r\n";
