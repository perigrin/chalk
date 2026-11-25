my @a=(1,2); sub z { $_[0]=9 } my @c=@a; z(@a); print "@c|@a\n";
