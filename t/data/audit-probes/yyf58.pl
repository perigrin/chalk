my @a=(1,2,3); for my $x (@a) { next if $x == 2; $x *= 10 } print "@a\n";
