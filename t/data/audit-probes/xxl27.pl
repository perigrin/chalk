my $s = ""; O: for my $i (1..3) { for my $j (1..3) { next O if $j > $i; last O if $i == 3; $s .= "$i$j" } } print "$s\n";
