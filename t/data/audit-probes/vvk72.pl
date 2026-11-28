my $s = ""; OUT: for my $i (1..3) { for my $j (1..3) { next OUT if $j == 2; last OUT if $i == 3; $s .= "$i$j," } } print "$s\n";
