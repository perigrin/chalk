my @a=(1,2); my @c=(my @d=@a); $a[0]=9; $d[1]=8; print "@c|@d\n";
