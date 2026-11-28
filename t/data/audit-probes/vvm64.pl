our $x = 1; sub f :lvalue { $x } { local $x = 2; f()++; print $x } print "$x\n";
