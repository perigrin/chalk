my @a = (1,2,3); sub f { $a[0]++; $_[0] } my @t = map { f($_) } @a; print "@t\n";
