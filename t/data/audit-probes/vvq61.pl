my %h = (a=>[1,2]); my %g = (l => [@{$h{a}}, "x"]); push @{$h{a}}, 3; print "@{$g{l}}\n";
