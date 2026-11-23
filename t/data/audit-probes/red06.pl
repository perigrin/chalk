use feature "try"; no warnings; our $g=1; try { local $g=2; die "a\n" } catch ($e) { print "c$g\n" } print "$g\n";
