our $g=1; eval { local $g=2; my $c = {}; $c->(); print "in\n" }; print "$g\n";
