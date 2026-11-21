our @a = (1); sub f { $a[0] = 5; 0 } print $a[0] + f(), "\n";
