our $v = 1; sub c { $v = 9; 0 } my $n = "v"; my @l = ($$n, c()); print "@l\n";
