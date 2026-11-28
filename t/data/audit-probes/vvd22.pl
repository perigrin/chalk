my %h = (a=>1,b=>2); @h{qw(a b)} = @h{qw(b a)}; print "$h{a}$h{b}\n";
