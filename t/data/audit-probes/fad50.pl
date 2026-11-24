our $g=1; sub f { local $g=2; return eval { die "x\n"; 1 } ? "a" : "b:$g" } print f(), " $g\n";
