my ($n,$m)=(0,0); for my $i (1..3) { for my $j (1..3) { last if $j==2; $n++ } $m+=$n } print "$n$m\n";
