my @a=(5,3,8); for my $i (0..$#a) { for my $j ($i+1..$#a) { @a[$i,$j]=@a[$j,$i] if $a[$j]<$a[$i] } } print "@a\n";
