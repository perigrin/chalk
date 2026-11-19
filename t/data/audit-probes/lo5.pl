our @a = (1,2,3); sub t { local $a[1] = 9; "@a" } print t(), "|@a\n";
