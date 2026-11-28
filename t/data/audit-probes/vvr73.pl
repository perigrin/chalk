my @a = (1,2,3); $_ *= 2 for @a[map { $_ } 1, 2]; print "@a\n";
