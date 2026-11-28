my %h = (a=>1,b=>2); $_ *= 2 for values %h; print "$h{a}$h{b}\n";
