my %h = (a=>1,b=>2,c=>3); my $k = "b"; delete @h{$k, "c"}; print join(",", keys %h), "\n";
