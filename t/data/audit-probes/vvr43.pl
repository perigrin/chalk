my @a = (1,2,3); sub md { shift @a; $_[0] = 9 } md($a[1]); print "@a\n";
