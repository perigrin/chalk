our %h=(a=>1); eval { local $h{a}=2; local $h{b}=3; die "x\n" }; print join(",",map{"$_$h{$_}"}sort keys %h),"\n";
