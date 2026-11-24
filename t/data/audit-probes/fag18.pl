my @a=(1,2); sub w { $a[0]=9 } my @c=reverse @a; w(); print "@c\n";
