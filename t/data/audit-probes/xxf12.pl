our $g = 1; sub f { local $g = 2; eval { die "d\n" }; $g } print f(), $g, "\n";
