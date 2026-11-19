my %h = (a=>1,b=>2); my $s = 0; for my $k (sort keys %h) { $s += $h{$k}; $h{$k} = 0 } print "$s $h{a}$h{b}\n";
