my %h = (a=>1); $h{b}{c} = 1; my @k = sort keys %h; print "@k", ref($h{b}), "\n";
