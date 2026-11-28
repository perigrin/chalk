my %h = (a=>1,b=>2); my $d = delete $h{a}; my $e = delete $h{zz}; print $d, defined $e ? "d" : "u", scalar(keys %h), "\n";
