my @a = (1,2,3); for my $i (0..$#a) { $a[$i + 1] = 9 if $i == 0; print $a[$i] } print "\n";
