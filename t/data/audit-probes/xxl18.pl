my $x = 0; my $c = sub { $x++ }; my $s = ""; for (1..3) { $s .= $x; $c->() } print "$s$x\n";
