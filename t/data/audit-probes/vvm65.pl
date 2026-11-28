our $x = 1; sub f :lvalue { $x } { local $x = 2; print f() } print "$x\n";
