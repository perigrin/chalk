my %h = (a=>1,b=>2,c=>3); my @big = grep { $h{$_} > 1 } sort keys %h; delete @h{@big}; print join(",", keys %h), "\n";
