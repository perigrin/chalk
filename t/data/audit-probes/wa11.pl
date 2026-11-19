my @a = (3,1,2); my @s = sort { $a <=> $b } @a; $a[0] = 0; print "@s|@a\n";
