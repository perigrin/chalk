my %h = (a=>1,b=>2); $_++ for @h{qw(a b)}; print "$h{a}$h{b}\n";
