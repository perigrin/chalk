my $z=0; my $t=0; for my $i (1..3) { $t+=$i; next if $i==2; $t += 6/($i-2); } print "$t\n";
