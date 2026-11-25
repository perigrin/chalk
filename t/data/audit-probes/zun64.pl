eval { eval { die "a\n" }; print "1:$@"; eval { die "b\n" }; print "2:$@"; }; print "3:[$@]\n";
