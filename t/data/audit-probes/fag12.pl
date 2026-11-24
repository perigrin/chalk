my @a=(1,2); sub w { $a[0]=9 } my @c=@a; for (1..2) { w() } print "@c\n";
