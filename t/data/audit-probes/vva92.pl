sub f { 1 } { local *f = sub { 2 }; print f() } print f(), "\n";
