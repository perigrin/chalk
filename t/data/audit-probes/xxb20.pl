my @a=(1,2,3); for my $i (0..$#a) { for (@a[$i..$#a]) { $_++ } } print "@a\n";
