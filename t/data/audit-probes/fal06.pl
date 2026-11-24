my %h=(a=>1,b=>2); for my $k (sort keys %h) { $h{$k}++; $h{"$k$k"}=0 } print join(",",map{"$_=$h{$_}"} sort keys %h),"\n";
