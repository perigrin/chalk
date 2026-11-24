sub f { die "f\n" } sub g { eval { f() }; print "g:$@"; die "g\n" } eval { g() }; print "m:$@";
