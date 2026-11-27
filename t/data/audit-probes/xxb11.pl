my @a=(1,2,3); my @b = grep { $_++ > 1 } @a; $b[0] = 99; print "@a|@b\n";
