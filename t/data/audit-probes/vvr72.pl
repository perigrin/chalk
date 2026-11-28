my @a = (1,2,3); $_ *= 2 for @a[grep { $_ } 0..2]; print "@a\n";
