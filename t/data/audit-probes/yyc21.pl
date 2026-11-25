sub inc { $_[0]++ } my ($a1,$b1,$c)=(1,2,0); inc($c ? $a1 : $b1); print "$a1 $b1\n";
