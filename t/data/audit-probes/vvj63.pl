my @a = (1,2,3); sub z0 { $a[0] = 0 } my $s = ""; for my $e (@a) { z0(); $s .= $e } print "$s\n";
