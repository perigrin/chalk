our $x = "a"; sub c { $x = "bb"; 2 } print ref(\$x) . c(), "\n";
