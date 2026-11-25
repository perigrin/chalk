our $g=1; sub p { $g } sub t { local $g = 2; eval { local $g = 3; die "x\n" }; p() } print t(), p(), "\n";
