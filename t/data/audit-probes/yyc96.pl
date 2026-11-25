sub f { print "f"; "k" } sub g { print "g"; 1 } my %h = (f() => g(), g() => f()); print " $h{k}\n";
