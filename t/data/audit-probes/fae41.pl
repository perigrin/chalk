my %h=(a=>1); eval { delete $h{a}; die "a\n" }; print exists $h{a}?1:0,"\n";
