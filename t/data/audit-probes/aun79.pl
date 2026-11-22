our $g=1; eval { local $g = 2; my @a = sort { die "x\n" } 2,1; }; print "$g\n";
