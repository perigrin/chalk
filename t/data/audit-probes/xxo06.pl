our %g = (a=>1,b=>2); { local @g{qw(a b)}; print defined $g{a} ? "d" : "u" } print "$g{a}$g{b}\n";
