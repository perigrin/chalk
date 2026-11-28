my $s = ""; OUT: for my $i (1..2) { my $j = 0; while (1) { $j++; next OUT if $j > $i; $s .= "$i$j," } } print "$s\n";
