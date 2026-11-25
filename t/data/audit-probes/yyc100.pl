sub c { print "c"; sub { print "x" } } sub a { print "a"; 1 } c()->(a()); print "\n";
