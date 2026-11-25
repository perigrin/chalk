my @r=eval { (1,2,die "x\n") }; print scalar(@r), "\n";
