my %h = (a=>1); sub k { $_[0] = 5 } k($h{a}); print "$h{a}\n";
