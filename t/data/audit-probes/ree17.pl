my @a=(1,2,3); for my $x (@a) { for my $y (@a) { $y++ if $x==1 } } print "@a\n";
