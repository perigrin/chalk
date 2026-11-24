my %h; for my $v (@h{qw(a b)}) { $v=1 } print join("",sort keys %h),"\n";
