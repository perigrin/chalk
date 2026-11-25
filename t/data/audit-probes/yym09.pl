my @a = (1..20); my @s = sort { ($a % 4) <=> ($b % 4) } @a; print "@s\n";
