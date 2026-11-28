our $x = 1; sub c { local $x = 3; 2 } print $x . c(), "\n";
