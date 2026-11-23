my $s=""; for my $i (1..5) { next if $i==2; last if $i==4; $s.=$i } continue { $s.="," } print "$s\n";
