my @a = (1,2,3); sub f { $_[0] .= "x" } sub g { f(@_) } for my $x (@a) { g($x) } print "@a\n";
