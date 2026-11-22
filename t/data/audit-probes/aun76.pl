use strict; our $g=1; eval { local $g = 2; my $r; my @l = @$r; print "in\n" }; print "$g\n";
