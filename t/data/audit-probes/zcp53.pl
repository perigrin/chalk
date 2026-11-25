our @a=(1,2); my @c=@a; sub w { push @a,3 } w(); print "@c|@a\n";
