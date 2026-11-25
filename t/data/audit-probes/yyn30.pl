my $s = ""; for my $i (1..3) { eval { $s .= "a$i"; die "x\n" if $i == 2; $s .= "b$i"; }; $s .= $@ ? "E" : "K" } print "$s\n";
