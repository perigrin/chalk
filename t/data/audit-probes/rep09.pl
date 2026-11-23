eval { my @a = map { die "m\n" } 1; }; print "[$@]\n";
