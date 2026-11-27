my @a = (1,2,3); my $i = 0; my $s = ""; while ($i < @a) { $s .= $a[$i]; pop @a if $i == 0; $i++ } print "$s\n";
