my @a = (1,2,3); sub f { $_[0] .= "x"; 1 } my @g = grep { f($_) } @a; print "@a|@g\n";
