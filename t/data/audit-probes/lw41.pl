sub bump { $_ .= "x" } my @a = (1,2); my @r; for my $i (1..2) { push @r, join(",", @a); my @m = map { bump(); $_ } @a } print "@r\n";
