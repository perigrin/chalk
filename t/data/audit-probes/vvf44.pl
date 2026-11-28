our $x = 1; sub c { $x = 3; 2 } print(($x .= 7) . c(), "\n");
