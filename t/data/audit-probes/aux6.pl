our $g=1; eval { local $g=2; my @a = (1,2); my @b = sort { $a->{k} <=> $b->{k} } @a; print "in\n" }; print "$g\n";
