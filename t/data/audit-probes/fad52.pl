our $g=1; sub f { local $g=2; my %h; my $v=$h{a}{b}; my $z=0; return 7 % $z } eval { f() }; print "$g\n";
