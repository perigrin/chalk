my %h = (a=>1,b=>2,c=>3); my @k = qw(b c); exists $h{$_} and delete $h{$_} for @k; print join(",", keys %h), "\n";
