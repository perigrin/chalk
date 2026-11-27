my @a=(1); sub f { $a[0]=7; 0 } my @l = ($a[0] = 5, f()); print "@l\n";
