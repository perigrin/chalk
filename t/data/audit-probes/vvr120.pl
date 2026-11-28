my %h = (a=>1,b=>2,c=>3); my @k = qw(a b c); delete @h{@k}; print scalar(keys %h), %h ? "t" : "f", "\n";
