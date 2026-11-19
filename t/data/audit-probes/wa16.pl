my %h = (a=>1,b=>2); my @k = sort keys %h; delete $h{a}; my @k2 = sort keys %h; print "@k|@k2\n";
