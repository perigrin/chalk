my ($s)=(""); OUT: for my $i (1..3) { for my $j (1..3) { last OUT if $i * $j == 4; $s .= "$i$j," } } print "$s\n";
