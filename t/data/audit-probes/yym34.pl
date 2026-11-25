my @a = (1,2); $_++ for map { $_ } @a; print "@a|"; $_++ for sort { $a <=> $b } @a; print "@a|"; $_++ for reverse @a; print "@a|"; $_++ for @a[0,1]; print "@a\n";
