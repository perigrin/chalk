my @a = (1,2); my @r; for my $i (1..2) { push @r, join(",", @a); $_ .= "x" for @a[0,1] } print "@r\n";
