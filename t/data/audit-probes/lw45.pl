my @a = (1,2); my @r; for my $i (1..2) { push @r, join(",", @a); my $j = 0; while ($j++ < 1) { push @a, $j } } print "@r\n";
