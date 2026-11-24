my %h; sub f { $h{a}=1; die "x\n" } eval { f(); $h{b}=2 }; print join(",",sort keys %h),"\n";
