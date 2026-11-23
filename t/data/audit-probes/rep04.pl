use feature "try"; no warnings; our $g = 1; try { local $g = 2; } catch ($e) { } print "$g\n";
