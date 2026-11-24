my @a=(1,2); sub w { $_[0][0]=9 } my @c=@a; w(\@a); print "@c\n";
