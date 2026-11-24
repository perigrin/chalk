my $x; eval { $x = [1,2]; die "x\n" }; print scalar(@$x),"\n";
