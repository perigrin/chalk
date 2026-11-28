our $x = 1; sub f :lvalue { $x } { local $x = 2; for (f()) { $_ = 5 } print $x } print "$x\n";
