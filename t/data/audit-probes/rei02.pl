our $n=0; sub b { $n*=2 } for my $i (1..3) { $n+=$i; b() } print "$n\n";
