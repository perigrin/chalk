my @a=(1,2); sub w { push @a,3 } my @c=@a; w(); print "@c\n";
