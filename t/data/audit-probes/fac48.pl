my %h=(a=>1); my %c=%h; for my $v (values %c) { $v=7 } print "$h{a}$c{a}\n";
