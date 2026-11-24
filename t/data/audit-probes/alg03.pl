our @a=(1,2); eval { for my $x (@a) { $x++; $x++; die "x\n" if $x > 2 } }; print "@a\n";
