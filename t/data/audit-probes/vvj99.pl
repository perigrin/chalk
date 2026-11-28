my @a = (10, 9, 100); my @s = sort @a; my @n = sort { $a <=> $b } @a; print "@s|@n\n";
