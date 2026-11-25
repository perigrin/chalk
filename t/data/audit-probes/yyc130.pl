my @a=(1,2,3); sub f { $a[0]=9; 0 } my @b=(@a, f()); print "@b\n";
