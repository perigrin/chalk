my @a=(1,2,3); for my $x (@a) { next if $x == 2; $x = 0 } print "@a\n";
