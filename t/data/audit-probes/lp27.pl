my @a = (1..5); my $s = 0; foreach my $i (0..$#a) { last if $a[$i] > 3; $s += $a[$i]; $a[$i+1] += 1 } print "$s @a\n";
