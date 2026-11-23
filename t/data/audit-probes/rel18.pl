my $s=""; for my $i (1..3) { $s.=$i; if ($i==2) { $s.="x"; next } $s.="y" } print "$s\n";
