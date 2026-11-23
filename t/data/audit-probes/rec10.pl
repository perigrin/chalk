our %g=(a=>1); sub f { local $g{a}=2; my $z=shift; 1/$z } eval { f(0) }; print "$g{a}\n";
