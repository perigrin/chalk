sub f { print "f"; 1 } sub g { print "g"; 2 } sub h { print "h"; 3 } my $n = f() ? g() : h(); print "$n\n";
