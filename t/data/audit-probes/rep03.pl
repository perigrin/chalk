our $g=1; eval { local $g = 2; f() }; sub f { 1 } print "$g\n";
