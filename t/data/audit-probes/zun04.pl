our %h=(k=>1); eval { local $h{k}=2; die "x\n" }; print "$h{k}\n";
