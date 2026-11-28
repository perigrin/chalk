my %h = (a=>1); sub ch { $_[1] = 2 } ch(%h); print "$h{a}\n";
