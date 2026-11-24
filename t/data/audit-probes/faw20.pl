my %h=(a=>1); my $c=0; if (%h) { $c++ } delete $h{a}; if (%h) { $c+=10 } unless (%h) { $c+=100 } print "$c\n";
