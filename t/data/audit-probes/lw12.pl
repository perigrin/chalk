sub bump { $_ .= "x" for @_ } my @a = (1,2); my @r; for my $i (1..2) { push @r, join(",", @a); bump(@a) } print "@r\n";
