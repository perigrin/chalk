our ($g,$k)=(1,1); sub f { local $g=2; { local $k=2; my $z=0; my $q=1/$z; } 1 } eval { f() }; print "$g$k\n";
