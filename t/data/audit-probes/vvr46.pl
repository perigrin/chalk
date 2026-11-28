my @a = (3,1,2); sub md { @a = sort { $a <=> $b } @a; $_[0] = 9 } md($a[0]); print "@a\n";
