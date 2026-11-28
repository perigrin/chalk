my %h = (a=>[1,2], b=>{c=>3}); my @f = (@{$h{a}}, %{$h{b}}); push @{$h{a}}, 3; print "@f", scalar(@{$h{a}}), "\n";
