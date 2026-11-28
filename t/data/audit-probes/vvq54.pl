my %h = (a=>[1,2]); my @l = (@{$h{a}}, "x"); $h{a} = [7]; print "@l\n";
