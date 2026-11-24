our %h=(a=>1); sub f { local $h{a}=2; local $h{b}=3; die "x\n" } eval { f() }; print join(",",map {"$_=$h{$_}"} sort keys %h),"\n";
