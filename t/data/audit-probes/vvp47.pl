my @a = (1,2); sub f { $a[-2] = 5; "@_" } print f(@a[0,1]), "\n";
