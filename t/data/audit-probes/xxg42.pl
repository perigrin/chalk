my @a = (1,2,3); my @l = (@a, push(@a, 4), @a); print scalar(@l), "\n";
