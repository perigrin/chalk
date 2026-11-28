my %h = (a=>[1,2]); my @l = (@{$h{a}}, 0); push @{$h{a}}, 3; print "@l\n";
