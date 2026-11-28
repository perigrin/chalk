our $x = 1; sub c { $x = 3; 3 } print(($x == c()) ? "eq" : "ne", "\n");
