our $g=1; sub dbl { $g*=2 } my $t=0; for (1..3) { $t+=$g; dbl() } print "$t $g\n";
