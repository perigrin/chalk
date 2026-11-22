our $g=1; sub t { local $g = 2; u() } sub u { die "x\n" } eval { t() }; print "$g\n";
