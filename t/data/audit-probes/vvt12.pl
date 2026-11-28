my @a = (1,2,3); sub f { $_[0] .= "x" } for (@a) { f($_) } print "@a\n";
