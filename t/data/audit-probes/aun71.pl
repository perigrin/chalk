our $g=1; sub u { 1 } sub t { local $g = 2; u(); return 5 } t(); print "$g\n";
