my %h = (a=>1,b=>2); my $d = delete $h{a}; my $n = delete $h{zz}; my @k = keys %h; %h = (); my $e = keys %h; undef %h; print $d, defined $n ? "d" : "u", "@k$e", scalar(keys %h), "\n";
