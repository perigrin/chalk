my @a = (1,2,3); my $s = ""; for my $i (0..$#a) { $s .= $a[$i]; $a[$i+1] = 7 if $i == 0 } print "$s\n";
