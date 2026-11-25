sub f { &g } sub g { "@_" } sub h { &g() } sub i { g(@_[1..$#_]) } sub j { goto &g } print f(1,2), "|", h(1,2), "|", i(1,2,3), "|", j(4,5), "\n";
