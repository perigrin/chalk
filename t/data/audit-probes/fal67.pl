my %h=(a=>1,b=>2,c=>3); for my $k (sort keys %h) { delete $h{$k} if $h{$k}%2 } print join("",sort keys %h),"\n";
