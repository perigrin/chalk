our $g = 1; sub t { local $g = 2; 1 } t(); print "$g\n";
