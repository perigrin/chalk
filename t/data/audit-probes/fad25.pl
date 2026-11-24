eval { die "x\n" }; eval { 1 }; print "[",$@,"]\n";
