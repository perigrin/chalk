my %h = (a=>1,b=>2,c=>3); delete $h{$_} for grep { $h{$_} % 2 } keys %h; print join(",", keys %h), "\n";
