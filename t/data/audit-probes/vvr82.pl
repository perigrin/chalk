my @a = (1,2,3); sub dbl { $_[0] *= 2 } dbl(@a[1..2]); print "@a\n";
