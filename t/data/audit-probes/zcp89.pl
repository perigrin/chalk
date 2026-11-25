my @a=(1,2); my @c=(1 ? @a : ()); $a[0]=9; print "@c\n";
