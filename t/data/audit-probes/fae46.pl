my $x=1; sub d { $x=5; die "a\n" } my @l = ($x+0, eval { d() }, $x+0); print "@l\n";
