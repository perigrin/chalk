my @a=(1,2); sub w { $a[0]=9 } my @c=(@a); w(); print "@c\n";
