my @a = (3,1,2); eval { @a = sort { die "x\n" if $a == 2; $a <=> $b } @a }; print "@a\n";
