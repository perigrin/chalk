my ($p,$q)=(1,2); eval { ($p,$q)=(5, die "x\n") }; print "$p$q\n";
