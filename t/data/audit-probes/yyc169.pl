our @a=(1,2); my @b=(@a, local $a[0]=9); print "@b\n";
