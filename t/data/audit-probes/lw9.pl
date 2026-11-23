sub bump { $_ .= "x" } my @a = (1,2); my @r; for my $i (1..2) { push @r, join(",", @a); for (@a) { bump() } } print "@r\n";
