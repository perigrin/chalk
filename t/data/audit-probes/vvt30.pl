my @a = (1,2,3); sub f { $_[0] .= "x" } sub g { f($_[$_]) for 0..$#_ } g(@a); print "@a\n";
