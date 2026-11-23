my @a = (1,2); my @r; while (1) { push @r, join(",", @a); last if @r == 2; for (@a) { $_ .= "x" } } print "@r\n";
