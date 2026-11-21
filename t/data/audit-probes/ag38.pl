my @a = (0); sub g { $_[0] = 5; "" } print $a[0], g(@a), "\n";
