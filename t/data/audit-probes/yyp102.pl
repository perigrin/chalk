my @a=(1,2,3); my @b=((grep { 1 } @a), $a[0]=9); print "@b\n";
