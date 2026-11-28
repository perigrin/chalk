my @a = (1,2,3); sub f { $_[0] .= "x" } sub g { for my $y (@_) { f($y) } } g(@a); print "@a\n";
