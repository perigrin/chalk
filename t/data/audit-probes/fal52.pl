our $g=1; my $t=0; for (1..3) { $t+=$g; $g*=2 if $_<3 } print "$t $g\n";
