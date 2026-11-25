our ($p,$q)=(1,2); sub s2 { "$p$q" } sub t { local ($p,$q) = (8,9); s2() } print t(), s2(), "\n";
