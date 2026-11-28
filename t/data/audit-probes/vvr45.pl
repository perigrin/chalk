my @a = (1,2,3); sub md { @a = reverse @a; $_[0] = 9 } md($a[0]); print "@a\n";
