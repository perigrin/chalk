my @a = (1,2); my @r; for (my $i = 0; $i < 2; $i++) { push @r, join(",", @a); for (@a) { $_ .= "x" } } print "@r\n";
