eval { my @a = sort { die "s\n" } 2,1; }; print "[$@]\n";
