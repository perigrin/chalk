our $g=1; sub t { my $r = eval { local $g = 2; 5 }; "$g$r" } print t(), "$g\n";
