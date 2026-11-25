my $x=1; sub f { &g; $_[0] } sub g { $_[0]=3 } print f($x),$x,"\n";
