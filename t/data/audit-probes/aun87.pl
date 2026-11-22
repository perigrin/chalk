our $g=1; sub t { local $g = 2; return eval { die "x\n"; 1 } ? "a" : "b$g" } print t(), $g, "\n";
