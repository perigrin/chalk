my @l = (eval { die "x\n" }, "after"); print scalar(@l), "\n";
