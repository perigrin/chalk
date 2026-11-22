my %h; my $r=\%h; (@$r{qw(a b)}) = (1,2); print join(",", map {"$_=$h{$_}"} sort keys %h),"\n";
