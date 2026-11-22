our $g=1; eval { local $g = 2; my $c = "nosuch"; $c->(); }; print "$g\n";
