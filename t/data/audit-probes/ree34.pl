my @a=(1,2,3); for my $x (grep { $_>1 } @a) { $x=0 } print "@a\n";
