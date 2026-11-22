our $g=1; eval { local $g=2; my $o = bless {}, "Nope"; $o->missing; print "in\n" }; print "$g\n";
