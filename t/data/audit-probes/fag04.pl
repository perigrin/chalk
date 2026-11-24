my @a=(1,2); sub w { $a[0]=9 } my @c=@a; w(); $c[1]=5; print "@c|@a\n";
