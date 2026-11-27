sub f { push @_, 9; $_[0] = 8 } my @a=(1,2); f(@a); print "@a\n";
