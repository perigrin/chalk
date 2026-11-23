my @a=(1,2,3); for my $x (@a) { last if $x==2; $x=0 } continue { $a[2]=8 } print "@a\n";
