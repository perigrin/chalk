my @a=(1,2,3); my @s = sort { ($b % 2) <=> ($a % 2) || $a <=> $b } @a; print "@s\n";
