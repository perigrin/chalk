sub f { for my $i (1..5) { for my $j (1..5) { return "$i$j" if $i*$j==6 } } "n" } print f(),"\n";
