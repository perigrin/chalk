our @a = (1,2,3); my $i = 0; while ($i++ < 2) { local @a = ($i); push @a, 0 } print "@a\n";
