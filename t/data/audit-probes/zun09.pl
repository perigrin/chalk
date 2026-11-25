sub f { local $\="!\n"; die "x\n" } eval { f() }; print "a"; print "\n";
