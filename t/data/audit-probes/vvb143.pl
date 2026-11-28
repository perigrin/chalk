my @a = (1,2,3); sub f { $_[0] *= 2 } map { f($_) } @a; print "@a\n";
