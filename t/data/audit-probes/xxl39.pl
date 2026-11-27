our $t = 0; sub add { $t += $_[0] } my $s = ""; for my $i (1..3) { $s .= $t . add($i) . $t } print "$s\n";
