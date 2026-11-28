my @a = (1,2,3); my @r = map { \$_ } @a; @a = reverse @a; ${$r[0]} = 9; print "@a\n";
