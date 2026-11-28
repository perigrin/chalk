our $g = 1; eval { local $g = 2; 1 } and print "$g\n";
