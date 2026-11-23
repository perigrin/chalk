my @a = (1,2); my @r; for my $i (1..2) { push @r, join(",", @a); local $a[0] = "L$i"; push @r, join(",", @a) } push @r, join(",", @a); print "@r\n";
