my @a = (1,2,3); sub f { $_[0] .= "x" } sub g { my @c = @_; f($_) for @c; "@c" } print g(@a), "|@a\n";
