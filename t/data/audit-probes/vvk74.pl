my $s = ""; my $i = 0; W: while ($i < 5) { $i++; for my $j (1..2) { next W if $i % 2; $s .= "$i$j," } } print "$s\n";
