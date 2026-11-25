my @a; for my $i (1..3) { my @b = (@a, $i); @a = @b } print "@a\n";
