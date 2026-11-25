sub f { shift; &g } sub g { scalar @_ } sub h { my $n = &g; shift; $n . &g } print f(1,2,3), h(1,2,3), "\n";
