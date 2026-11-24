my @a=(1,2); eval { for my $x (@a) { $x*=5; die "x\n" if $x>5 } }; print "@a\n";
