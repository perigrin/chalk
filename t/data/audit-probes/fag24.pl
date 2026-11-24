my @a=(1,2); sub w { $a[0]=9 } my @c=@a; print "@c\n"; w(); print "@c\n";
