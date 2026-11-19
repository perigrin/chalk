our $g = 1; sub t { local $g; $g = 5; return if $_[0]; $g = 6; return } t(1); print "$g"; t(0); print "$g\n";
