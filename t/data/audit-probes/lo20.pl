our $g = 1; for my $i (1..2) { local $g = $g + $i; print "in $g\n"; last if $i == 2; print "more\n"; } print "$g\n";
