my ($a1,$b1); $b1=2; sub inc { $_[0]++ } inc($a1 // $b1); print defined $a1 ? $a1 : "u", "$b1\n";
