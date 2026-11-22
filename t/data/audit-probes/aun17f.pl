our ($a1, $b1) = (1, 2); sub sw { ($a1, $b1) = ($b1, $a1) } my $s = "$a1$b1"; sw(); print "$s $a1$b1\n";
