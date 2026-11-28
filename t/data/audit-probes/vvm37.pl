our @a = (1,2,3); for my $i (1..2) { local @a = (@a, $i); print scalar(@a) } print scalar(@a), "\n";
