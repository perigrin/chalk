my %h = (a=>[1,2], b=>{c=>3}); my @l = (@{$h{a}}, %{$h{b}}); print "@l\n";
