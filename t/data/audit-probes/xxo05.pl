our %g = (a=>1,b=>2); { local @g{qw(a b)} = (8,9); print "$g{a}$g{b}" } print "$g{a}$g{b}\n";
