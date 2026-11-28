my @a = (1,2,3); my $r = \@a; my $q = [@$r]; $q->[0] = 9; print "@a\n";
