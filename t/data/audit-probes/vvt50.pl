my @a = (1,2,3); sub f { $a[0]++; $_[0] } my @t = grep { f($_) > 2 } @a; print "@t\n";
