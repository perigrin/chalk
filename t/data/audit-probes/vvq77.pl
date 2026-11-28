my %h = (a=>[1,2]); my @l = (@{$h{a}}, scalar(@{$h{a}})); push @{$h{a}}, 3; print "@l\n";
