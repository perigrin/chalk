my ($a1,$b1)=(1,2); sub cc { 0 } (cc() ? $a1 : $b1) = 6; print "$a1 $b1\n";
