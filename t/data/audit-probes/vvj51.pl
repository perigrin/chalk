my @a = (3,1,2); $_ *= 2 for sort { $a <=> $b } @a; print "@a\n";
