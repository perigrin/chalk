my @a=(1); sub w { push @a,1 } for (1..2) { print scalar(@a); w() } print "\n";
