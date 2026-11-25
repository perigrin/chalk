my %h=(a=>1,b=>2); my @k=sort keys %h; delete $h{a}; print scalar(@k), "\n";
