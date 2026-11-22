use strict; our $g=1; eval { local $g=2; my $n = "name"; my $v = $$n; print "in\n" }; print "$g\n";
