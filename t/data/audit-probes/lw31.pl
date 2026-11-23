my @a = (1,2); my @r; for my $i (1..2) { push @r, join(",", @a); (my $f, @a) = (0, map { $_ . "x" } @a) } print "@r\n";
