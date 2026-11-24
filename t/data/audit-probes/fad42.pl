my $s=""; for my $i (1..3) { eval { $s.=$i; last if $i==2; }; $s.="." } print "$s\n";
