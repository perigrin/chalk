my %h = (a=>1,b=>2); for my $k (sort keys %h) { $h{$k} *= 2 } print "$h{a}$h{b}\n";
