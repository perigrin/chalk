my %h = (a=>1,b=>2); %h = (%h, c=>3); %h = reverse %h; print join(",", map {"$_$h{$_}"} sort keys %h), "\n";
