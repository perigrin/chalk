my @a = (1,2,3); sub f { $_[0] .= "x" } map { f($_) } @a; print "@a\n";
