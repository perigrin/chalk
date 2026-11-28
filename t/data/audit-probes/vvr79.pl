my @a = (1,2,3); map { $_ *= 2 } @a[1..$#a]; print "@a\n";
