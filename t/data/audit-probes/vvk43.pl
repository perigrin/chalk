my @a = (3, 1, 2); my @s = sort { $a <=> $b } @a; $s[0] = 9; print "@a\n";
