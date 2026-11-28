my @a = (3,1,2); @a = sort { $a <=> $b } @a; my @b = @a; @b = reverse @b; print "@a|@b\n";
