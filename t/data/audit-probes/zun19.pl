eval { local $@; eval { die "x\n" }; 1 }; print "[$@]\n";
