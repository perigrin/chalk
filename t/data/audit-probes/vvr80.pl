my @a = (1,2,3); my @g = grep { $_ *= 2 } @a[1..$#a]; print "@a|@g\n";
