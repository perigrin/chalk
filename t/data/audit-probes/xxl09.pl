my %h = (a=>1); my $n = 0; while (keys %h) { my ($k) = keys %h; delete $h{$k}; $h{"b$n"} = 1 if $n++ < 2 } print "$n\n";
