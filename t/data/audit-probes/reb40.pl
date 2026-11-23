our ($a1,$b1)=(1,2); eval { local ($a1,$b1)=(3,4); die "x\n" }; print "$a1 $b1\n";
