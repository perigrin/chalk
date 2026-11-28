my %h = (a=>[1,2]); my @l = (@{$h{a}}, "x"); $h{a}[0] = 9; print "@l\n";
