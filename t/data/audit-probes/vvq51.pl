my %h = (a=>[1,2], b=>[5]); my @l = (@{$h{a}}, @{$h{b}}); push @{$h{a}}, 3; print "@l\n";
