my @a=(1,2); sub f { $_[0]=2; die "x\n" } eval { f($_) for @a }; print "@a\n";
