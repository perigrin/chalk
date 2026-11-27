my @a=(1,2,3); sub f { $a[0]=9 } my @b=(@a[0,1], f()); print "@b\n";
