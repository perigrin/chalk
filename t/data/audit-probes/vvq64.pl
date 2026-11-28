my @d = ([1,2]); my @l = (@{$d[0]}, "x"); push @{$d[0]}, 3; print "@l\n";
