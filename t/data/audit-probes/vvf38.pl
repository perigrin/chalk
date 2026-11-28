our $x = "a"; sub c { $x = "bb"; 2 } print ${\ "$x"} . c(), "\n";
