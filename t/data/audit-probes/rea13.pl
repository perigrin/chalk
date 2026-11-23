my $i=0; my $s=0; while (1) { $i++; next if $i%2; last if $i>6; $s+=$i } print "$s $i\n";
