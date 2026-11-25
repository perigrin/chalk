sub f { print "f"; "a" } sub g { print "g"; "b" } my $s = f() . g() . f(); print " $s\n";
