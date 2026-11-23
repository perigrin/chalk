use feature "try"; no warnings; my $x=0; try { $x=1; } catch ($e) { } finally { print "fin\n" } print "$x\n";
