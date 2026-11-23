our $g=1; sub f { local $g=2; my $z = shift; 1/$z } my $v = f(1); print "$g $v\n";
