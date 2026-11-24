my @a=(1,2); sub w { $a[0]=9 } my @c=(0,@a); w(); print "@c\n";
