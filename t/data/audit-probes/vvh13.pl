my $s = ""; for my $i (1..3) { eval { $s .= $i; die "z\n" if $i == 2; $s .= "k" }; $s .= "e" if $@ } print "$s\n";
