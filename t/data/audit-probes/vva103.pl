our %h = (a=>1,b=>2); my $k = "a"; { local $h{$k} = 9; $k = "b"; print "$h{a}$h{b};" } print "$h{a}$h{b}\n";
