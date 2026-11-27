our %g = (a=>1,b=>2); my @k = qw(a b); { local @g{@k} = (8,9); } print "$g{a}$g{b}\n";
