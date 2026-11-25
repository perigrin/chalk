our $g="o"; sub show { $g } sub f { local $g="i"; eval { die "x\n" }; show() } print f(), show(), "\n";
