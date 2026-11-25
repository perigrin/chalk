sub f { print "f"; "-" } sub g { print "g"; 1 } sub h { print "h"; 2 } my $s = join(f(), g(), h()); print " $s\n";
