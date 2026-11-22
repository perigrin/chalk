our $g = 1; try_it(); sub try_it { eval { local $g = 2; 1 } or print "no\n"; print "$g\n" }
