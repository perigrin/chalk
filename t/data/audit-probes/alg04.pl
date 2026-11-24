my @a=(1,2,3); eval { for my $x (@a) { next if $x == 2; $x *= 10; die "x\n" if $x == 30 } }; print "@a\n";
