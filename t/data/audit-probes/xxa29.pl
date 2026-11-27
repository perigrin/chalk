sub f { $_[0] = "x" } my @a=(1,2); f(@a[1,0]); print "@a\n";
