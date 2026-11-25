my @a=(1,2,3); sub z { $_=0 for @_ } z(@a[1,2]); print "@a\n";
