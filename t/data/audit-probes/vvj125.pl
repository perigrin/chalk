my %h = (a=>1,b=>2); for my $v (map { $_ } values %h) { $v++ } print "$h{a}$h{b}\n";
