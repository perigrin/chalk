my %h = (a=>[1,2], b=>{c=>3}); my @l = (%{$h{b}}, @{$h{a}}); push @{$h{a}}, 3; print "@l\n";
