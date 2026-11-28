our $x = 1; sub f :lvalue { $x } { local $x; f() = 5; } print "$x\n";
