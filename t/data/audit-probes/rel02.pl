my $s=""; OUTER: for my $i (1..3) { for my $j (1..3) { next OUTER if $j==2; last OUTER if $i==3; $s.="$i$j," } } print "$s\n";
