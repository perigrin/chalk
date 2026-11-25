eval { die "a\n" }; eval { 1 }; print "[$@]\n";
