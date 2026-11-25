my @a=(1,2,3); my @b=((map { $_ } @a), $a[0]=9); print "@b\n";
