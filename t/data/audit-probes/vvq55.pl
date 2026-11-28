my %h = (a=>[1,2]); my @l = (@{$h{a}}, "x"); pop @{$h{a}}; print "@l\n";
