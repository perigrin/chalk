my @a = (1,2,3); sub md { splice(@a, 0, 1); $_[0] = 9 } md($a[2]); print "@a\n";
