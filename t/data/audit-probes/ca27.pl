sub f { goto &g } sub g { "g:@_" } print f(1,2), "\n";
