our $g = 1; sub t { local $g = 2; u() } sub u { local $g = 3; die "x\n" } eval { t() }; print "$g\n";
