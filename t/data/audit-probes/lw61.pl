my @a = (1,2); my @b = (3); my @r; for my $i (1..2) { push @r, join(",", @a, @b); for (@b) { $_ .= "y" } } print "@r\n";
