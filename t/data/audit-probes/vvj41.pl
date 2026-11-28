my @a = (1,2,3); for my $i (reverse 0..$#a) { $a[$i] = $a[$i - 1] if $i } print "@a\n";
