our $g="o"; sub show { $g } sub f { local $g="i"; show() } print f(), show(), "\n";
