our $x = "a"; sub c { $x = "bb"; 2 } print defined($x) . c(), "\n";
