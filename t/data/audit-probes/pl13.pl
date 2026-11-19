our ($a1, $b1) = (0, 0); sub sw { ($a1, $b1) = ($b1 + 1, $a1 + 2) } for (1..3) { $a1 = $a1 + 1; sw() } print "$a1 $b1\n";
