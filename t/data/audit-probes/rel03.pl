my ($i,$s)=(0,0); while ($i<10) { $i++; if ($i%2) { next } elsif ($i>6) { last } $s+=$i } print "$s $i\n";
