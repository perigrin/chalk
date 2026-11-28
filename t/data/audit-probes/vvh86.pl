our $x = 1; sub c { $x = 2; die "x\n" } my @l = ($x, eval { c() }, $x); print "@l\n";
