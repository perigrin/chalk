my @a = (1,2,3); sub dbl { $_ *= 2 for @_ } dbl(@a[1..$#a]); print "@a\n";
