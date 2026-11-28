my @a = (1,2,3); sub z2 { $a[2] = 0 } my $s = ""; for my $e (@a) { z2(); $s .= $e } print "$s\n";
