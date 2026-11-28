my @a = (1,2,3); my ($lo, $hi) = (1, 2); $_ *= 2 for @a[$lo..$hi]; print "@a\n";
