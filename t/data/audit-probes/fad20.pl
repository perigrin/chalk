our $g=1; my $s=""; for my $i (1..3) { local $g=$g+$i; next if $i==2; $s.=$g } print "$s $g\n";
