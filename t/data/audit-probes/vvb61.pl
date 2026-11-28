my @a = (1,2,3); my @r = map { \$_ } @a; ${$r[1]} = 9; print "@a\n";
