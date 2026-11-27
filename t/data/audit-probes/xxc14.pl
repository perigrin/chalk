my @a=(3,1,2); my @s = sort { $a <=> $b } grep { $_ > 1 } @a; print "@s\n";
