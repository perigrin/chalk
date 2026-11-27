my %h = (a=>1,b=>2); { local @h{qw(a b)} = (8,9); print "$h{a}$h{b}" } print "$h{a}$h{b}\n";
