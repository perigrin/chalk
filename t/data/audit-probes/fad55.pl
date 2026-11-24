our $g=1; sub f { local $g=2; my $z=0; my $q = eval { 1/$z } // 0; my $w=1/$z; } eval { f() }; print "$g\n";
