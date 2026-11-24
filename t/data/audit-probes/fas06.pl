our $x=1; sub rd { $x } sub t { local $x=2; rd() } print t(), rd(), "\n";
