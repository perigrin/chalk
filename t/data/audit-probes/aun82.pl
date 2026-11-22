use strict; our $g=1; eval { local $g = 2; my @a=(1); my $x = $a[0]{k}; print "in\n" }; print "$g\n";
