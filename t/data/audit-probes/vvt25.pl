my @a = (1,2,3); sub f { $_[0] .= "x" } sub g { f($_[0]) } for my $x (@a) { g($x) } print "@a\n";
