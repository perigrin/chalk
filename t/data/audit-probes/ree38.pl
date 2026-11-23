my @a=(1,2,3); OUT: for my $x (@a) { for my $y (1,2) { $x.="a"; next OUT if $y==1 } } print "@a\n";
