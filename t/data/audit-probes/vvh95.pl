my $n = 0; my @a = (1,2,3); eval { for my $e (@a) { $e *= 2; die "x\n" if $e == 4 } }; print "@a\n";
