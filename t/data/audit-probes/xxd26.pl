my $x = 1; sub wr2 { $x = shift } my @l = ($x, wr2(5), $x); print "@l\n";
