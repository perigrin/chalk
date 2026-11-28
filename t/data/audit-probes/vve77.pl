my $x = 1; sub f { $x = 5; g(@_) } sub g { $_[0] } print f($x), "\n";
