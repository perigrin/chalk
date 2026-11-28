my @a = (1,2,3); my @r = grep { $$_ > 1 } map { \$_ } @a; ${$r[0]}++; print "@a\n";
