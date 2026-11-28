my @a = (3, 1, 2); my @s = sort { $a <=> $b } @a; print "@s|", defined $a ? "d" : "u", "\n";
