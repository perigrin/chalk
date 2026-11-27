my $i=7; my $c = sub { $i }; for $i (1..2) { print $c->() } print "\n";
