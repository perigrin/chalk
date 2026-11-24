use feature 'try'; no warnings; my $s=""; for my $i (1..3) { try { die "x\n" if $i==2; $s.=$i } catch ($e) { next } $s.="." } print "$s\n";
