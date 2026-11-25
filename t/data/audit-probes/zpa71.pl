my @a=(1,2); my @b=grep { $_ *= 2; 1 } @a; $b[0]=0; print "@a|@b\n";
