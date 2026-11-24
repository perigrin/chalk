my @a=(1,2); sub w { $a[0]=9 } my @c=@a[0,1]; w(); print "@c\n";
