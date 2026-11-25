my ($a1,$b1)=(0,2); sub inc { $_[0]++ } inc($a1 || $b1); print "$a1$b1\n";
