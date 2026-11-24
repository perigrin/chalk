my @a=(1,2,3); for my $x (@a) { $x*=2; push @a, 0 if @a<4 } print "@a\n";
