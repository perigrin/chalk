our $x = "a"; sub c { $x = "b"; 2 } print length($x) . c(), "\n";
