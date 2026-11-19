sub f { $_[0]++ } my @a = (1,2); f($a[1]); f($_) for @a; print "@a\n";
