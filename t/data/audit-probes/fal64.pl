my @a=(1,2,3); my $max=$a[0]; for my $i (1..$#a) { $max=$a[$i] if $a[$i]>$max; $a[$i]=0 } print "$max @a\n";
