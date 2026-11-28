my %h = (a=>1,b=>2,c=>3); my @k = qw(b c); delete %h{@k}; print join(",", keys %h), "\n";
