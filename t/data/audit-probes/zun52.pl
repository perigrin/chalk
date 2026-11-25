our ($p,$q)=(1,2); eval { local ($p,$q)=(8,9); die "x\n" }; print "$p$q\n";
