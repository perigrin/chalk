my %h=(a=>1,b=>2); for my $v (values %h) { $v*=3 } print join(",",map{$h{$_}}sort keys %h),"\n";
