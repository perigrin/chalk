my @a=(1,2); sub w { $a[1]="z" } my @c=@a; w(); my @d=@a; print "@c|@d\n";
