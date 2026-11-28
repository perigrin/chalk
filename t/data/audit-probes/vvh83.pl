my $x = 1; my @l = ($x, eval { $x = 2; die "x\n" }, $x); print "@l\n";
