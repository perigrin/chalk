my @a = (1,2); sub g { $_[0] = 5 } sub f { g($a[-2]); $_[0] } print f($a[0]), "\n";
