eval { eval { die "in\n" }; print "1:$@"; die "out\n" }; print "2:$@";
