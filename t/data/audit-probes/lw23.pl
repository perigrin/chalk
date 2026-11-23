my @a = (1,2); my @r; for my $i (1..2) { push @r, join(",", @a); @a[0,1] = ("p$i","q$i") } print "@r\n";
