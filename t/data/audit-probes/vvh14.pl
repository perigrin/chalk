my $s = ""; for my $i (1..3) { eval { die "z$i\n" if $i % 2 }; $s .= $@ ? "e" : "o" } print "$s\n";
