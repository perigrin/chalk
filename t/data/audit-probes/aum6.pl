our $g=1; eval { local $g = 2; print "in$g\n" }; print "$g\n";
