my @a = (0); sub f { $a[0] = $_[0] + 1; $_[0] } print f(1), $a[0], f(0), $a[0]; print "\n";
