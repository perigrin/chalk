my @a=(1,2,3); my @b=(@a, do { $a[0] = 9 }); print "@b\n";
