our $x = 1; sub c { $x++; 2 } print $x + c() + c() + $x, "\n";
