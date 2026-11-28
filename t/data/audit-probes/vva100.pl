our %h = (a=>1,b=>2); for my $k (sort keys %h) { local $h{$k} = 0; print "$h{a}$h{b};" } print "$h{a}$h{b}\n";
