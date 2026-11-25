my @a=(1,2,3); my $t=0; for my $i (0..$#a) { for my $j ($i+1..$#a) { $t+=$a[$i]*$a[$j] } } print "$t\n";
