my %h = (a=>[1,2], b=>{c=>3}); my @l = (@{$h{a}}, %{$h{b}}); $h{b}{d} = 4; print scalar(@l), "\n";
