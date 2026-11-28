my %h = (a=>1,b=>2,c=>3); my @k = qw(b c); undef @h{@k}; print join(",", map { defined $h{$_} ? "d" : "u" } sort keys %h), "\n";
