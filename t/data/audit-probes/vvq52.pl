my %h = (a=>[1,2], b=>{c=>3}); my @l = (@{$h{a}}, %{$h{b}}); push @{$h{a}}, 3; print "@l\n";
