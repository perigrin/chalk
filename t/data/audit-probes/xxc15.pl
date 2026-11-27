my @a=(3,1,2); my @s = map { $_ * 2 } sort { $a <=> $b } @a; print "@s\n";
