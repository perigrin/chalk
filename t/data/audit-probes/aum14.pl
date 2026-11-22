my @a = (1); eval { my @b = map { die "m\n" if $_; $_ } @a; print "no\n" }; print "[$@]\n";
