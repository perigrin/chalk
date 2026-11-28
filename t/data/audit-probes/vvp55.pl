my @a = (1,2); sub g { $a[-2] = 5 } sub f { g(); $_[0] } print f($a[0]), "\n";
