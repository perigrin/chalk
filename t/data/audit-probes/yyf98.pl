my ($i,$j,$s)=(0,0,""); OUT: while ($i < 3) { $i++; $j=0; while ($j < 3) { $j++; next OUT if $j == 2; $s .= "$i$j" } } print "$s\n";
