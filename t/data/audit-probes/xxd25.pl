my $x = 1; sub rd { $x } sub wr { $x = shift } wr(5); my $v = rd() + $x; wr(6); print "$v$x\n";
