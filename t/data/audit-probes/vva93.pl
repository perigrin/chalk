sub f { 1 } { no warnings; local *f = sub { 2 }; print main->can("f")->() } print f(), "\n";
