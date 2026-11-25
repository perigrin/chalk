my %h=(a=>1,b=>2); for my $k (sort keys %h) { delete $h{b} if $k eq "a"; print exists $h{$k} ? $k : "-" } print "\n";
