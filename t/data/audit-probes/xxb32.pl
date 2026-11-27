my @a=(1,2,3); my @b = map { \$_ } @a; ${$b[1]} = 9; print "@a\n";
