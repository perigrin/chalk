our $g=1; sub f { local $g=2; eval { die "z\n" }; $g } print f(), " $g\n";
