my $i=7; sub w { $i=9 } for $i (1..2) { w() } print "$i\n";
