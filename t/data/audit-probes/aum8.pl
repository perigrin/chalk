our $g=1; eval { eval { local $g = 2; 1 }; print "mid$g\n"; 1 }; print "$g\n";
