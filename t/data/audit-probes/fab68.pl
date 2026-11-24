my %h=(a=>1,b=>2,c=>3); my @v=@h{qw(a c)}; delete @h{qw(a b)}; print "@v ", join("",keys %h), "\n";
