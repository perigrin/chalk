my @a = (1,2,3); my @r; for my $i (1..2) { push @r, join(",", @a); @a = reverse @a } print "@r\n";
