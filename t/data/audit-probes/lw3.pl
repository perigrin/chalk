my @a = (1,2); my @r; for my $i (1..2) { push @r, "@a"; $_ *= 2 for @a } print "@r\n";
