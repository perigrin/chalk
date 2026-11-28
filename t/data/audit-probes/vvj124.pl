my %h = (a=>1,b=>2); for my $v (@h{qw(a zz)}) { $v = 7 } print join(",", map {"$_$h{$_}"} sort keys %h), "\n";
