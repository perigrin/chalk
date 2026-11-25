my @a=(3,1,2); my @c=@a; @a=sort { $a <=> $b } @a; print "@c|@a\n";
