my @a=(1,2); sub w { $a[0]=9 } my @c=@a; if (@c) { w() } print "@c\n";
