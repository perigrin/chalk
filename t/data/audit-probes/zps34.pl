my ($n,$m)=(0,0); OUTER: for my $i (1..3) { for my $j (1..3) { next OUTER if $j==2; $n++ } $m++ } print "$n$m\n";
