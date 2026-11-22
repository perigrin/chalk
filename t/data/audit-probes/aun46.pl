my %h=(a=>1); my $v = delete($h{a}) . (exists $h{a} ? "y":"n"); print "$v\n";
